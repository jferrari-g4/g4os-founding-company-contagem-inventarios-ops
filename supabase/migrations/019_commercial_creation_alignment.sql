-- Alinha a criação comercial: permite somente o INSERT inicial do dimensionamento e a geração automática de tarefas.

drop policy if exists dimensionings_operational_insert on public.dimensionings;
create policy dimensionings_operational_insert on public.dimensionings for insert to authenticated with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational')
  or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);

create or replace function public.sync_project_tasks(p_project_id uuid,p_inventory_start date default null)
returns integer language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_type text;
  v_count integer;
begin
  if not (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('coordinator')) then
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

revoke all on function public.sync_project_tasks(uuid,date) from public,anon;
grant execute on function public.sync_project_tasks(uuid,date) to authenticated;
