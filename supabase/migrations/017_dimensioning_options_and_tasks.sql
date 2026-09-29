-- Completa o dimensionamento com opções aprováveis e cria tarefas configuráveis por tipo de inventário.

create table if not exists public.task_templates (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  inventory_type text,
  due_days_before_inventory integer check (due_days_before_inventory is null or due_days_before_inventory >= 0),
  responsible_role text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  template_id uuid references public.task_templates(id) on delete set null,
  title text not null,
  description text,
  responsible_role text,
  responsible_name text,
  due_at timestamptz,
  status text not null default 'pending' check (status in ('pending','in_progress','completed','waived')),
  completed_by uuid references public.profiles(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,template_id)
);

create index if not exists task_templates_inventory_type_idx on public.task_templates(inventory_type,active,sort_order);
create index if not exists project_tasks_project_status_idx on public.project_tasks(project_id,status,due_at);

drop trigger if exists task_templates_updated on public.task_templates;
create trigger task_templates_updated before update on public.task_templates for each row execute procedure public.set_updated_at();
drop trigger if exists project_tasks_updated on public.project_tasks;
create trigger project_tasks_updated before update on public.project_tasks for each row execute procedure public.set_updated_at();

alter table public.task_templates enable row level security;
alter table public.project_tasks enable row level security;

drop policy if exists task_templates_read on public.task_templates;
create policy task_templates_read on public.task_templates for select to authenticated using (true);
drop policy if exists task_templates_admin_write on public.task_templates;
create policy task_templates_admin_write on public.task_templates for all to authenticated
using (private.has_role('admin'))
with check (private.has_role('admin'));

drop policy if exists project_tasks_read on public.project_tasks;
create policy project_tasks_read on public.project_tasks for select to authenticated using (true);
drop policy if exists project_tasks_operational_write on public.project_tasks;
create policy project_tasks_operational_write on public.project_tasks for all to authenticated
using (
  private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor')
  or private.has_role('operational_manager') or private.has_role('coordinator')
)
with check (
  private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor')
  or private.has_role('operational_manager') or private.has_role('coordinator')
);

create or replace function public.save_dimensioning_draft(
  p_project_id uuid,
  p_options jsonb,
  p_selected_option_id uuid default null,
  p_visit_starts timestamptz[] default array[]::timestamptz[],
  p_notes text default null
)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_dimensioning_id uuid;
  v_option jsonb;
  v_option_id uuid;
  v_visit_count integer:=coalesce(array_length(p_visit_starts,1),0);
  v_index integer;
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode editar o dimensionamento.';
  end if;
  if jsonb_typeof(coalesce(p_options,'[]'::jsonb))<>'array' then raise exception 'As opções de dimensionamento devem ser uma lista.'; end if;
  if v_visit_count>2 then raise exception 'Informe no máximo duas opções de visita.'; end if;

  perform 1 from public.projects where id=p_project_id and status='awaiting_dimensioning' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando dimensionamento.'; end if;

  insert into public.dimensionings(project_id,status,opened_at,notes)
  values(p_project_id,'in_progress',now(),nullif(trim(p_notes),''))
  on conflict(project_id) do update set status=case when public.dimensionings.status='open' then 'in_progress' else public.dimensionings.status end,notes=coalesce(nullif(trim(p_notes),''),public.dimensionings.notes)
  returning id into v_dimensioning_id;

  for v_option in select value from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) loop
    v_option_id=(v_option->>'id')::uuid;
    if nullif(trim(v_option->>'title'),'') is null then raise exception 'Toda opção de dimensionamento precisa de um título.'; end if;
    if exists(select 1 from public.dimensioning_options where id=v_option_id and dimensioning_id<>v_dimensioning_id) then
      raise exception 'Uma opção enviada não pertence a este dimensionamento.';
    end if;
    insert into public.dimensioning_options(id,dimensioning_id,title,days,team_size,details,approved,approved_by,approved_at)
    values(
      v_option_id,v_dimensioning_id,trim(v_option->>'title'),nullif(v_option->>'days','')::integer,
      nullif(v_option->>'team_size','')::integer,
      jsonb_build_object('notes',coalesce(v_option->>'notes','')),
      v_option_id=p_selected_option_id,
      case when v_option_id=p_selected_option_id then auth.uid() else null end,
      case when v_option_id=p_selected_option_id then now() else null end
    )
    on conflict(id) do update set
      title=excluded.title,days=excluded.days,team_size=excluded.team_size,details=excluded.details,
      approved=excluded.approved,approved_by=excluded.approved_by,approved_at=excluded.approved_at;
  end loop;

  delete from public.dimensioning_options option_row
   where option_row.dimensioning_id=v_dimensioning_id
     and not exists(select 1 from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) item where (item->>'id')::uuid=option_row.id);

  if p_selected_option_id is not null and not exists(
    select 1 from public.dimensioning_options where id=p_selected_option_id and dimensioning_id=v_dimensioning_id
  ) then raise exception 'A opção de dimensionamento selecionada não pertence ao projeto.'; end if;

  if v_visit_count=0 then
    delete from public.date_options where project_id=p_project_id;
  else
    for v_index in 1..v_visit_count loop
      insert into public.date_options(project_id,option_number,starts_at,proposed_by,status,sent_at)
      values(p_project_id,v_index,p_visit_starts[v_index],auth.uid(),'proposed',now())
      on conflict(project_id,option_number) do update set starts_at=excluded.starts_at,proposed_by=auth.uid(),status='proposed',sent_at=now(),selected_at=null,selected_by=null;
    end loop;
    delete from public.date_options where project_id=p_project_id and option_number>v_visit_count;
  end if;

  update public.dimensionings set
    status=case when p_selected_option_id is null then 'in_progress' else 'awaiting_approval' end,
    notes=coalesce(nullif(trim(p_notes),''),notes)
  where id=v_dimensioning_id;

  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('dimensionings',p_project_id,'draft_saved',jsonb_build_object('selected_option_id',p_selected_option_id,'visit_option_count',v_visit_count),auth.uid());
end;
$$;

create or replace function public.complete_dimensioning(p_project_id uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_updated integer;
  v_project public.projects%rowtype;
  v_dimensioning_id uuid;
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode concluir o dimensionamento.';
  end if;
  select * into v_project from public.projects where id=p_project_id and status='awaiting_dimensioning' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando dimensionamento.'; end if;
  select id into v_dimensioning_id from public.dimensionings where project_id=p_project_id for update;
  if not found then raise exception 'O dimensionamento precisa existir antes da conclusão.'; end if;
  if not exists(select 1 from public.dimensioning_options where dimensioning_id=v_dimensioning_id and approved=true) then
    raise exception 'Selecione a opção de dimensionamento aprovada antes de concluir.';
  end if;
  if (select count(*) from public.date_options where project_id=p_project_id and starts_at is not null)<2 then
    raise exception 'Registre duas opções de visita antes de concluir o dimensionamento.';
  end if;

  update public.dimensionings set status='approved',completed_at=now(),approved_by=auth.uid(),approved_at=now(),notes=coalesce(nullif(trim(p_notes),''),notes) where id=v_dimensioning_id and status in ('open','in_progress','awaiting_approval');
  get diagnostics v_updated=row_count;
  if v_updated=0 then raise exception 'O dimensionamento não está em uma etapa válida para conclusão.'; end if;

  insert into public.ti_validations(project_id,status,required,system_name,ti_contact_name,ti_contact_email,ti_contact_phone,notes)
  values(p_project_id,'pending',true,v_project.layout_system,v_project.ti_contact_name,v_project.ti_contact_email,v_project.ti_contact_phone,null)
  on conflict(project_id) do update set status='pending',required=true,system_name=coalesce(public.ti_validations.system_name,excluded.system_name),ti_contact_name=coalesce(public.ti_validations.ti_contact_name,excluded.ti_contact_name),ti_contact_email=coalesce(public.ti_validations.ti_contact_email,excluded.ti_contact_email),ti_contact_phone=coalesce(public.ti_validations.ti_contact_phone,excluded.ti_contact_phone),validated_by=null,validated_at=null;

  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  update public.projects set status='awaiting_ti',operational_notes=coalesce(nullif(trim(p_notes),''),operational_notes),updated_by=auth.uid(),updated_at=now() where id=p_project_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('dimensionings',p_project_id,'approved',jsonb_build_object('dimensioning_id',v_dimensioning_id),auth.uid());
end;
$$;

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

  insert into public.project_tasks(project_id,template_id,title,description,responsible_role,due_at)
  select p_project_id,t.id,t.title,t.description,t.responsible_role,
    case when p_inventory_start is null or t.due_days_before_inventory is null then null
      else ((p_inventory_start-t.due_days_before_inventory)::date+time '18:00') at time zone 'America/Sao_Paulo' end
  from public.task_templates t
  where t.active=true and (t.inventory_type is null or lower(trim(t.inventory_type))=lower(trim(coalesce(v_type,''))))
  on conflict(project_id,template_id) do update set
    title=excluded.title,description=excluded.description,responsible_role=excluded.responsible_role,
    due_at=case when p_inventory_start is null then public.project_tasks.due_at else excluded.due_at end,
    updated_at=now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

revoke all on function public.save_dimensioning_draft(uuid,jsonb,uuid,timestamptz[],text) from public,anon;
grant execute on function public.save_dimensioning_draft(uuid,jsonb,uuid,timestamptz[],text) to authenticated;
revoke all on function public.complete_dimensioning(uuid,text) from public,anon;
grant execute on function public.complete_dimensioning(uuid,text) to authenticated;
revoke all on function public.sync_project_tasks(uuid,date) from public,anon;
grant execute on function public.sync_project_tasks(uuid,date) to authenticated;
