-- Fecha lacunas finais de integridade: transições somente por RPC e validações server-side.

-- Nenhum perfil atualiza projects diretamente; criação continua via INSERT e gates via RPC security definer.
drop policy if exists projects_update_open on public.projects;

create or replace function public.start_dimensioning(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode iniciar o dimensionamento.';
  end if;
  perform 1 from public.projects where id=p_project_id and status='received' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está disponível para iniciar o dimensionamento.'; end if;

  insert into public.dimensionings(project_id,status,opened_at)
  values(p_project_id,'in_progress',now())
  on conflict(project_id) do update set status=case when public.dimensionings.status in ('open','rejected') then 'in_progress' else public.dimensionings.status end;

  update public.projects set status='awaiting_dimensioning',updated_by=auth.uid(),updated_at=now() where id=p_project_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('dimensionings',p_project_id,'started',jsonb_build_object('status','awaiting_dimensioning'),auth.uid());
end;
$$;

create or replace function public.complete_dimensioning(p_project_id uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_updated integer;
  v_project public.projects%rowtype;
  v_dimensioning_id uuid;
  v_option_count integer;
  v_approved_count integer;
  v_visit_count integer;
  v_distinct_visits integer;
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode concluir o dimensionamento.';
  end if;
  select * into v_project from public.projects where id=p_project_id and status='awaiting_dimensioning' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando dimensionamento.'; end if;
  select id into v_dimensioning_id from public.dimensionings where project_id=p_project_id for update;
  if not found then raise exception 'O dimensionamento precisa existir antes da conclusão.'; end if;

  select count(*),count(*) filter(where approved=true)
    into v_option_count,v_approved_count
    from public.dimensioning_options
   where dimensioning_id=v_dimensioning_id;
  if v_option_count<2 then raise exception 'Cadastre ao menos duas opções de dimensionamento antes de concluir.'; end if;
  if v_approved_count<>1 then raise exception 'Selecione exatamente uma opção de dimensionamento aprovada.'; end if;
  if exists(select 1 from public.dimensioning_options where dimensioning_id=v_dimensioning_id and (nullif(trim(title),'') is null or days is null or days<=0 or team_size is null or team_size<=0)) then
    raise exception 'Todas as opções precisam de título, dias positivos e equipe positiva.';
  end if;

  select count(*),count(distinct starts_at) into v_visit_count,v_distinct_visits
    from public.date_options where project_id=p_project_id and starts_at is not null;
  if v_visit_count<2 then raise exception 'Registre duas opções de visita antes de concluir o dimensionamento.'; end if;
  if v_distinct_visits<2 then raise exception 'As duas opções de visita precisam ter datas e horários distintos.'; end if;

  update public.dimensionings set status='approved',completed_at=now(),approved_by=auth.uid(),approved_at=now(),notes=coalesce(nullif(trim(p_notes),''),notes)
   where id=v_dimensioning_id and status in ('open','in_progress','awaiting_approval');
  get diagnostics v_updated=row_count;
  if v_updated=0 then raise exception 'O dimensionamento não está em uma etapa válida para conclusão.'; end if;

  insert into public.ti_validations(project_id,status,required,system_name,ti_contact_name,ti_contact_email,ti_contact_phone,notes)
  values(p_project_id,'pending',true,v_project.layout_system,v_project.ti_contact_name,v_project.ti_contact_email,v_project.ti_contact_phone,null)
  on conflict(project_id) do update set status='pending',required=true,system_name=coalesce(public.ti_validations.system_name,excluded.system_name),ti_contact_name=coalesce(public.ti_validations.ti_contact_name,excluded.ti_contact_name),ti_contact_email=coalesce(public.ti_validations.ti_contact_email,excluded.ti_contact_email),ti_contact_phone=coalesce(public.ti_validations.ti_contact_phone,excluded.ti_contact_phone),validated_by=null,validated_at=null;

  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  update public.projects set status='awaiting_ti',operational_notes=coalesce(nullif(trim(p_notes),''),operational_notes),updated_by=auth.uid(),updated_at=now() where id=p_project_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('dimensionings',p_project_id,'approved',jsonb_build_object('dimensioning_id',v_dimensioning_id,'option_count',v_option_count,'visit_count',v_visit_count),auth.uid());
end;
$$;

create or replace function public.approve_ti_validation(p_project_id uuid,p_system_name text default null,p_notes text default null)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_project public.projects%rowtype;
  v_ti public.ti_validations%rowtype;
begin
  if not (private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas TI ou gestores autorizados podem validar o projeto.';
  end if;
  select * into v_project from public.projects where id=p_project_id and status='awaiting_ti' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando validação de TI.'; end if;

  update public.ti_validations set system_name=coalesce(nullif(trim(p_system_name),''),system_name),notes=coalesce(nullif(trim(p_notes),''),notes) where project_id=p_project_id;
  select * into v_ti from public.ti_validations where project_id=p_project_id;
  if not found then raise exception 'Salve a validação de TI antes de aprovar.'; end if;
  if nullif(trim(v_ti.system_name),'') is null then raise exception 'Informe o sistema ou layout validado.'; end if;
  if nullif(trim(v_ti.ti_contact_name),'') is null then raise exception 'Informe o nome do contato de TI.'; end if;
  if nullif(trim(v_ti.ti_contact_email),'') is null then raise exception 'Informe o e-mail do contato de TI.'; end if;
  if exists(select 1 from public.date_options where project_id=p_project_id) then
    if v_project.selected_date_option_id is null then raise exception 'Selecione uma das opções de visita antes de aprovar TI.'; end if;
    if not exists(select 1 from public.date_options where id=v_project.selected_date_option_id and project_id=p_project_id and status='selected') then
      raise exception 'A visita selecionada não pertence a este projeto ou não foi confirmada.';
    end if;
  end if;

  update public.ti_validations set status='approved',validated_by=auth.uid(),validated_at=now() where project_id=p_project_id;
  insert into public.plannings(project_id,status,started_by) values(p_project_id,'in_progress',auth.uid())
  on conflict(project_id) do update set status=case when public.plannings.status in ('draft','in_progress') then 'in_progress' else public.plannings.status end;
  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  update public.projects set status='planning',updated_by=auth.uid(),updated_at=now() where id=p_project_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('ti_validations',p_project_id,'approved',jsonb_build_object('system_name',v_ti.system_name,'selected_date_option_id',v_project.selected_date_option_id),auth.uid());
end;
$$;

revoke all on function public.start_dimensioning(uuid) from public,anon;
grant execute on function public.start_dimensioning(uuid) to authenticated;
revoke all on function public.complete_dimensioning(uuid,text) from public,anon;
grant execute on function public.complete_dimensioning(uuid,text) to authenticated;
revoke all on function public.approve_ti_validation(uuid,text,text) from public,anon;
grant execute on function public.approve_ti_validation(uuid,text,text) to authenticated;
