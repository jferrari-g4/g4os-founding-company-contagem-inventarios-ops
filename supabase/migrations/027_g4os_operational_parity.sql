-- Paridade operacional do MCP com a plataforma. Todas as funções deste arquivo
-- são exclusivas do service_role; o ator vem da conexão individual validada pela Edge Function.

create or replace function private.g4os_assume_actor(p_actor_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if p_actor_id is null or not exists(select 1 from public.user_roles where user_id=p_actor_id) then
    raise exception 'Ator G4 OS inválido ou sem perfil.';
  end if;
  perform set_config('request.jwt.claim.sub',p_actor_id::text,true);
end;
$$;
revoke all on function private.g4os_assume_actor(uuid) from public,anon,authenticated;
grant execute on function private.g4os_assume_actor(uuid) to service_role;

create or replace function public.g4os_start_dimensioning(p_actor_id uuid,p_project_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.g4os_assume_actor(p_actor_id); perform public.start_dimensioning(p_project_id); end $$;
create or replace function public.g4os_save_dimensioning_draft(p_actor_id uuid,p_project_id uuid,p_options jsonb,p_selected_option_id uuid,p_visit_starts timestamptz[],p_notes text)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$ declare v_id uuid; begin perform private.g4os_assume_actor(p_actor_id); select public.save_dimensioning_draft(p_project_id,p_options,p_selected_option_id,p_visit_starts,p_notes) into v_id; return v_id; end $$;
create or replace function public.g4os_complete_dimensioning(p_actor_id uuid,p_project_id uuid,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.g4os_assume_actor(p_actor_id); perform public.complete_dimensioning(p_project_id,p_notes); end $$;
create or replace function public.g4os_save_ti_validation_draft(p_actor_id uuid,p_project_id uuid,p_system_name text,p_ti_contact_name text,p_ti_contact_email text,p_ti_contact_phone text,p_notes text,p_selected_date_option_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$ declare v_id uuid; begin perform private.g4os_assume_actor(p_actor_id); select public.save_ti_validation_draft(p_project_id,p_system_name,p_ti_contact_name,p_ti_contact_email,p_ti_contact_phone,p_notes,p_selected_date_option_id) into v_id; return v_id; end $$;
create or replace function public.g4os_approve_ti_validation(p_actor_id uuid,p_project_id uuid,p_system_name text,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.g4os_assume_actor(p_actor_id); perform public.approve_ti_validation(p_project_id,p_system_name,p_notes); end $$;
create or replace function public.g4os_approve_planning(p_actor_id uuid,p_project_id uuid,p_content jsonb,p_completion_percentage numeric)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.g4os_assume_actor(p_actor_id); perform public.approve_planning(p_project_id,p_content,p_completion_percentage); end $$;
create or replace function public.g4os_sync_project_tasks(p_actor_id uuid,p_project_id uuid,p_inventory_start date)
returns integer language plpgsql security definer set search_path=public,private,pg_catalog as $$ declare v_count integer; begin perform private.g4os_assume_actor(p_actor_id); select public.sync_project_tasks(p_project_id,p_inventory_start) into v_count; return v_count; end $$;

create or replace function public.g4os_save_planning_draft(p_actor_id uuid,p_project_id uuid,p_content jsonb,p_completion_percentage numeric)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_id uuid;v_status public.project_status;
begin
  perform private.g4os_assume_actor(p_actor_id);
  if not (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then raise exception 'Seu perfil não pode editar o planejamento.'; end if;
  if jsonb_typeof(p_content)<>'object' then raise exception 'Conteúdo do planejamento inválido.'; end if;
  select status into v_status from public.projects where id=p_project_id and deleted_at is null for update;
  if v_status not in ('planning','awaiting_dates') then raise exception 'O planejamento não está liberado para edição.'; end if;
  insert into public.plannings(project_id,content,status,completion_percentage,started_by,updated_at)
  values(p_project_id,p_content,'in_progress',greatest(0,least(100,coalesce(p_completion_percentage,0))),p_actor_id,now())
  on conflict(project_id) do update set content=excluded.content,status='in_progress',completion_percentage=excluded.completion_percentage,updated_at=now(),version=coalesce(public.plannings.version,0)+1,started_by=coalesce(public.plannings.started_by,p_actor_id)
  returning id into v_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('plannings',v_id,'g4os_draft_saved',jsonb_build_object('project_id',p_project_id,'completion_percentage',p_completion_percentage),p_actor_id);
  return v_id;
end;
$$;

create or replace function public.g4os_update_project_task(p_actor_id uuid,p_task_id uuid,p_status text,p_responsible_name text,p_due_at timestamptz,p_set_due boolean default false)
returns public.project_tasks language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_task public.project_tasks;
begin
  perform private.g4os_assume_actor(p_actor_id);
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('coordinator')) then raise exception 'Seu perfil não pode alterar tarefas operacionais.'; end if;
  if p_status is not null and p_status not in ('pending','in_progress','completed','waived') then raise exception 'Status de tarefa inválido.'; end if;
  update public.project_tasks set
    status=coalesce(p_status,status),responsible_name=case when p_responsible_name is null then responsible_name else nullif(btrim(p_responsible_name),'') end,
    due_at=case when p_set_due then p_due_at else due_at end,due_overridden=case when p_set_due then true else due_overridden end,
    completed_at=case when p_status='completed' then now() when p_status is not null then null else completed_at end,
    completed_by=case when p_status='completed' then p_actor_id when p_status is not null then null else completed_by end,updated_at=now()
  where id=p_task_id returning * into v_task;
  if v_task.id is null then raise exception 'Tarefa não encontrada.'; end if;
  return v_task;
end;
$$;

create or replace function public.g4os_upsert_custom_field(p_actor_id uuid,p_field_id uuid,p_field_key text,p_label text,p_required boolean,p_active boolean,p_show_when_dimensioning boolean,p_sort_order integer)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$ declare v_id uuid; begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem gerenciar campos.'; end if;
  if btrim(coalesce(p_label,''))='' then raise exception 'Rótulo obrigatório.'; end if;
  if p_field_id is null then insert into public.custom_fields(entity,field_key,label,field_type,required,active,sort_order,system_field,show_when_dimensioning) values('project',coalesce(nullif(btrim(p_field_key),''),'custom_'||replace(gen_random_uuid()::text,'-','')),btrim(p_label),'text',coalesce(p_required,false),coalesce(p_active,true),coalesce(p_sort_order,0),false,coalesce(p_show_when_dimensioning,false)) returning id into v_id;
  else update public.custom_fields set label=btrim(p_label),required=coalesce(p_required,required),active=coalesce(p_active,active),sort_order=coalesce(p_sort_order,sort_order),show_when_dimensioning=coalesce(p_show_when_dimensioning,show_when_dimensioning) where id=p_field_id returning id into v_id; end if;
  if v_id is null then raise exception 'Campo não encontrado.'; end if;return v_id;
end $$;
create or replace function public.g4os_delete_custom_field(p_actor_id uuid,p_field_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem excluir campos.'; end if;delete from public.custom_fields where id=p_field_id and not system_field;if not found then raise exception 'Campo não encontrado ou protegido.';end if;end $$;

create or replace function public.g4os_upsert_task_template(p_actor_id uuid,p_template_id uuid,p_title text,p_description text,p_inventory_type text,p_due_days_before_inventory integer,p_responsible_role text,p_active boolean,p_sort_order integer)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$ declare v_id uuid;begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem gerenciar modelos de tarefas.'; end if;if btrim(coalesce(p_title,''))='' then raise exception 'Título obrigatório.'; end if;if p_due_days_before_inventory is not null and p_due_days_before_inventory<0 then raise exception 'Prazo relativo inválido.';end if;
  if p_template_id is null then insert into public.task_templates(title,description,inventory_type,due_days_before_inventory,responsible_role,active,sort_order,created_by,updated_by) values(btrim(p_title),nullif(btrim(p_description),''),nullif(btrim(p_inventory_type),''),p_due_days_before_inventory,nullif(btrim(p_responsible_role),''),coalesce(p_active,true),coalesce(p_sort_order,0),p_actor_id,p_actor_id) returning id into v_id;
  else update public.task_templates set title=btrim(p_title),description=nullif(btrim(p_description),''),inventory_type=nullif(btrim(p_inventory_type),''),due_days_before_inventory=p_due_days_before_inventory,responsible_role=nullif(btrim(p_responsible_role),''),active=coalesce(p_active,active),sort_order=coalesce(p_sort_order,sort_order),updated_by=p_actor_id,updated_at=now() where id=p_template_id returning id into v_id;end if;if v_id is null then raise exception 'Modelo não encontrado.';end if;return v_id;
end $$;

-- Nenhum wrapper pode ser chamado pela API pública/autenticada.
do $$ declare r record;begin for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'g4os_%' loop execute format('revoke all on function %s from public,anon,authenticated',r.signature);execute format('grant execute on function %s to service_role',r.signature);end loop;end $$;
