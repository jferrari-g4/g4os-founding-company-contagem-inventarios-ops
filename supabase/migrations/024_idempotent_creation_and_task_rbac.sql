-- Idempotência da criação e separação do recálculo de tarefas por papel.

alter table public.projects add column if not exists request_key uuid;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.projects'::regclass and conname='projects_request_key_key') then
    alter table public.projects add constraint projects_request_key_key unique(request_key);
  end if;
end $$;

drop function if exists public.create_project_request(text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,text,jsonb,jsonb);

create or replace function public.create_project_request(
  p_request_key uuid,
  p_cnpj text,
  p_cnpj_raw text,
  p_legal_name text,
  p_trade_name text default null,
  p_address text default null,
  p_contact_name text default null,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_inventory_type text default null,
  p_layout_system text default null,
  p_ti_contact_name text default null,
  p_ti_contact_email text default null,
  p_ti_contact_phone text default null,
  p_requires_dimensioning boolean default true,
  p_operational_notes text default null,
  p_field_values jsonb default '[]'::jsonb,
  p_planning_content jsonb default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_client_id uuid;
  v_project_id uuid;
  v_contact_id uuid;
  v_status public.project_status;
  v_field jsonb;
begin
  if p_request_key is null then raise exception 'Chave idempotente obrigatória.'; end if;
  select id into v_project_id from public.projects where request_key=p_request_key;
  if found then return v_project_id; end if;

  if not (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Seu perfil não pode criar solicitações.';
  end if;
  if nullif(regexp_replace(coalesce(p_cnpj,''),'\D','','g'),'') is null or length(regexp_replace(p_cnpj,'\D','','g'))<>14 then
    raise exception 'Informe um CNPJ válido com 14 dígitos.';
  end if;
  if nullif(trim(p_legal_name),'') is null then raise exception 'Informe a razão social.'; end if;
  if nullif(trim(p_contact_name),'') is null or nullif(trim(p_contact_email),'') is null then
    raise exception 'Informe nome e e-mail do contato principal.';
  end if;
  if jsonb_typeof(coalesce(p_field_values,'[]'::jsonb))<>'array' then raise exception 'Valores de campos inválidos.'; end if;

  insert into public.clients(cnpj,cnpj_raw,legal_name,trade_name,address)
  values(regexp_replace(p_cnpj,'\D','','g'),p_cnpj_raw,trim(p_legal_name),nullif(trim(p_trade_name),''),nullif(trim(p_address),''))
  on conflict(cnpj) do update set legal_name=excluded.legal_name,trade_name=excluded.trade_name,address=excluded.address,cnpj_raw=excluded.cnpj_raw,updated_at=now()
  returning id into v_client_id;

  select id into v_contact_id from public.client_contacts where client_id=v_client_id and is_primary=true order by id limit 1 for update;
  if v_contact_id is null then
    insert into public.client_contacts(client_id,name,email,phone,is_primary)
    values(v_client_id,trim(p_contact_name),nullif(trim(p_contact_email),''),nullif(trim(p_contact_phone),''),true)
    returning id into v_contact_id;
  else
    update public.client_contacts set name=trim(p_contact_name),email=nullif(trim(p_contact_email),''),phone=nullif(trim(p_contact_phone),'') where id=v_contact_id;
  end if;

  v_status=case when p_requires_dimensioning then 'received'::public.project_status else 'planning'::public.project_status end;
  insert into public.projects(request_key,client_id,inventory_type,layout_system,ti_contact_name,ti_contact_email,ti_contact_phone,requires_dimensioning,status,operational_notes,created_by,updated_by)
  values(p_request_key,v_client_id,nullif(trim(p_inventory_type),''),nullif(trim(p_layout_system),''),nullif(trim(p_ti_contact_name),''),nullif(trim(p_ti_contact_email),''),nullif(trim(p_ti_contact_phone),''),p_requires_dimensioning,v_status,nullif(trim(p_operational_notes),''),auth.uid(),auth.uid())
  on conflict(request_key) do nothing
  returning id into v_project_id;
  if v_project_id is null then
    select id into v_project_id from public.projects where request_key=p_request_key;
    return v_project_id;
  end if;

  for v_field in select value from jsonb_array_elements(coalesce(p_field_values,'[]'::jsonb)) loop
    if nullif(v_field->>'field_id','') is not null then
      insert into public.project_field_values(project_id,field_id,value)
      values(v_project_id,(v_field->>'field_id')::uuid,v_field->'value')
      on conflict(project_id,field_id) do update set value=excluded.value;
    end if;
  end loop;

  if p_requires_dimensioning then
    insert into public.dimensionings(project_id,status,opened_at,due_at)
    values(v_project_id,'open',now(),now()+interval '24 hours');
    if p_planning_content is not null then
      insert into public.plannings(project_id,content,status,started_by)
      values(v_project_id,p_planning_content,'draft',auth.uid());
    end if;
  else
    insert into public.plannings(project_id,content,status,started_by)
    values(v_project_id,coalesce(p_planning_content,'{}'::jsonb),'draft',auth.uid());
  end if;

  insert into public.project_tasks(project_id,template_id,title,description,responsible_role,due_at,due_overridden)
  select v_project_id,t.id,t.title,t.description,t.responsible_role,null,false
  from public.task_templates t
  where t.active=true and (t.inventory_type is null or lower(trim(t.inventory_type))=lower(trim(coalesce(p_inventory_type,''))))
  on conflict(project_id,template_id) do nothing;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('projects',v_project_id,'request_created',jsonb_build_object('requires_dimensioning',p_requires_dimensioning,'status',v_status),auth.uid());
  return v_project_id;
end;
$$;

revoke all on function public.create_project_request(uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,text,jsonb,jsonb) from public,anon;
grant execute on function public.create_project_request(uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,text,jsonb,jsonb) to authenticated;


create or replace function public.sync_project_tasks(p_project_id uuid,p_inventory_start date default null)
returns integer language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_type text;
  v_count integer;
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('coordinator')) then
    raise exception 'Seu perfil não pode sincronizar tarefas operacionais.';
  end if;
  select inventory_type into v_type from public.projects where id=p_project_id and deleted_at is null;
  if not found then raise exception 'Projeto não encontrado.'; end if;
  insert into public.project_tasks(project_id,template_id,title,description,responsible_role,due_at,due_overridden)
  select p_project_id,t.id,t.title,t.description,t.responsible_role,
    case when p_inventory_start is null or t.due_days_before_inventory is null then null else ((p_inventory_start-t.due_days_before_inventory)::date+time '18:00') at time zone 'America/Sao_Paulo' end,false
  from public.task_templates t
  where t.active=true and (t.inventory_type is null or lower(trim(t.inventory_type))=lower(trim(coalesce(v_type,''))))
  on conflict(project_id,template_id) do update set
    title=excluded.title,description=excluded.description,responsible_role=excluded.responsible_role,
    due_at=case when public.project_tasks.due_overridden then public.project_tasks.due_at when p_inventory_start is null then public.project_tasks.due_at else excluded.due_at end,
    updated_at=now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.sync_project_tasks(uuid,date) from public,anon;
grant execute on function public.sync_project_tasks(uuid,date) to authenticated;
