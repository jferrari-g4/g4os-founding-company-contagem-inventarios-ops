-- Substitui escrita ampla por políticas compatíveis com rascunho e aprovação via RPC.
drop policy if exists authenticated_write_plannings on public.plannings;
drop policy if exists planning_insert_draft on public.plannings;
drop policy if exists planning_update_draft on public.plannings;
drop policy if exists planning_delete_admin on public.plannings;

create policy planning_insert_draft on public.plannings
for insert to authenticated
with check (public.is_authenticated() and status in ('draft','in_progress','awaiting_checklists','awaiting_approval'));

create policy planning_update_draft on public.plannings
for update to authenticated
using (public.is_authenticated() and status in ('draft','in_progress','awaiting_checklists','awaiting_approval'))
with check (public.is_authenticated() and status in ('draft','in_progress','awaiting_checklists','awaiting_approval'));

create policy planning_delete_admin on public.plannings
for delete to authenticated
using (private.is_admin() and status not in ('approved','published'));

drop policy if exists authenticated_write_projects on public.projects;
drop policy if exists projects_insert_open on public.projects;
drop policy if exists projects_update_open on public.projects;
drop policy if exists projects_delete_admin on public.projects;

create policy projects_insert_open on public.projects
for insert to authenticated
with check (public.is_authenticated() and status <> 'confirmed');

create policy projects_update_open on public.projects
for update to authenticated
using (public.is_authenticated() and status <> 'confirmed')
with check (public.is_authenticated() and status <> 'confirmed');

create policy projects_delete_admin on public.projects
for delete to authenticated
using (private.is_admin() and status <> 'confirmed');
