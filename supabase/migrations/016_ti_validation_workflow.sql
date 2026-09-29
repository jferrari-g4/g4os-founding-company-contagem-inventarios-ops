-- Estrutura o gate TI/Datas: rascunho, seleção da visita e aprovação validada.

create or replace function public.complete_dimensioning(p_project_id uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_updated integer;
  v_project public.projects%rowtype;
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode concluir o dimensionamento.';
  end if;

  select * into v_project from public.projects where id=p_project_id and status='awaiting_dimensioning' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando dimensionamento.'; end if;

  update public.dimensionings
     set status='approved',completed_at=now(),approved_by=auth.uid(),approved_at=now(),notes=coalesce(nullif(trim(p_notes),''),notes)
   where project_id=p_project_id and status in ('open','in_progress','awaiting_approval');
  get diagnostics v_updated=row_count;
  if v_updated=0 then raise exception 'O dimensionamento precisa existir e estar aberto antes da conclusão.'; end if;

  insert into public.ti_validations(project_id,status,required,system_name,ti_contact_name,ti_contact_email,ti_contact_phone,notes)
  values(p_project_id,'pending',true,v_project.layout_system,v_project.ti_contact_name,v_project.ti_contact_email,v_project.ti_contact_phone,null)
  on conflict(project_id) do update set
    status='pending',
    required=true,
    system_name=coalesce(public.ti_validations.system_name,excluded.system_name),
    ti_contact_name=coalesce(public.ti_validations.ti_contact_name,excluded.ti_contact_name),
    ti_contact_email=coalesce(public.ti_validations.ti_contact_email,excluded.ti_contact_email),
    ti_contact_phone=coalesce(public.ti_validations.ti_contact_phone,excluded.ti_contact_phone),
    validated_by=null,
    validated_at=null;

  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  update public.projects
     set status='awaiting_ti',operational_notes=coalesce(nullif(trim(p_notes),''),operational_notes),updated_by=auth.uid(),updated_at=now()
   where id=p_project_id;
end;
$$;

create or replace function public.save_ti_validation_draft(
  p_project_id uuid,
  p_system_name text,
  p_ti_contact_name text,
  p_ti_contact_email text,
  p_ti_contact_phone text default null,
  p_notes text default null,
  p_selected_date_option_id uuid default null
)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_project public.projects%rowtype;
begin
  if not (private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas TI ou gestores autorizados podem editar a validação.';
  end if;

  select * into v_project from public.projects where id=p_project_id and status='awaiting_ti' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando validação de TI.'; end if;

  if p_selected_date_option_id is not null and not exists(
    select 1 from public.date_options where id=p_selected_date_option_id and project_id=p_project_id
  ) then
    raise exception 'A opção de visita selecionada não pertence a este projeto.';
  end if;

  insert into public.ti_validations(project_id,status,required,system_name,ti_contact_name,ti_contact_email,ti_contact_phone,notes,validated_by,validated_at)
  values(p_project_id,'pending',true,nullif(trim(p_system_name),''),nullif(trim(p_ti_contact_name),''),nullif(trim(p_ti_contact_email),''),nullif(trim(p_ti_contact_phone),''),nullif(trim(p_notes),''),null,null)
  on conflict(project_id) do update set
    status='pending',required=true,
    system_name=excluded.system_name,
    ti_contact_name=excluded.ti_contact_name,
    ti_contact_email=excluded.ti_contact_email,
    ti_contact_phone=excluded.ti_contact_phone,
    notes=excluded.notes,
    validated_by=null,
    validated_at=null;

  update public.projects set
    layout_system=nullif(trim(p_system_name),''),
    ti_contact_name=nullif(trim(p_ti_contact_name),''),
    ti_contact_email=nullif(trim(p_ti_contact_email),''),
    ti_contact_phone=nullif(trim(p_ti_contact_phone),''),
    selected_date_option_id=p_selected_date_option_id,
    updated_by=auth.uid(),updated_at=now()
  where id=p_project_id;

  if p_selected_date_option_id is not null then
    update public.date_options set
      status=case when id=p_selected_date_option_id then 'selected' else 'proposed' end,
      selected_at=case when id=p_selected_date_option_id then now() else null end,
      selected_by=case when id=p_selected_date_option_id then auth.uid() else null end
    where project_id=p_project_id;
  end if;

  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('ti_validations',p_project_id,'draft_saved',jsonb_build_object('system_name',p_system_name,'selected_date_option_id',p_selected_date_option_id),auth.uid());
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

  update public.ti_validations set
    system_name=coalesce(nullif(trim(p_system_name),''),system_name),
    notes=coalesce(nullif(trim(p_notes),''),notes)
  where project_id=p_project_id;

  select * into v_ti from public.ti_validations where project_id=p_project_id;
  if not found then raise exception 'Salve a validação de TI antes de aprovar.'; end if;
  if nullif(trim(v_ti.system_name),'') is null then raise exception 'Informe o sistema ou layout validado.'; end if;
  if nullif(trim(v_ti.ti_contact_name),'') is null then raise exception 'Informe o nome do contato de TI.'; end if;
  if nullif(trim(v_ti.ti_contact_email),'') is null then raise exception 'Informe o e-mail do contato de TI.'; end if;
  if exists(select 1 from public.date_options where project_id=p_project_id) and v_project.selected_date_option_id is null then
    raise exception 'Selecione uma das opções de visita antes de aprovar TI.';
  end if;

  update public.ti_validations set status='approved',validated_by=auth.uid(),validated_at=now() where project_id=p_project_id;
  insert into public.plannings(project_id,status,started_by)
  values(p_project_id,'in_progress',auth.uid())
  on conflict(project_id) do update set status=case when public.plannings.status in ('draft','in_progress') then 'in_progress' else public.plannings.status end;

  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  update public.projects set status='planning',updated_by=auth.uid(),updated_at=now() where id=p_project_id;

  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('ti_validations',p_project_id,'approved',jsonb_build_object('system_name',v_ti.system_name,'selected_date_option_id',v_project.selected_date_option_id),auth.uid());
end;
$$;

revoke all on function public.save_ti_validation_draft(uuid,text,text,text,text,text,uuid) from public,anon;
grant execute on function public.save_ti_validation_draft(uuid,text,text,text,text,text,uuid) to authenticated;
revoke all on function public.complete_dimensioning(uuid,text) from public,anon;
revoke all on function public.approve_ti_validation(uuid,text,text) from public,anon;
grant execute on function public.complete_dimensioning(uuid,text) to authenticated;
grant execute on function public.approve_ti_validation(uuid,text,text) to authenticated;
