-- Evita policies permissivas duplicadas em SELECT e otimiza auth.uid()/FK da alocação.
create index if not exists project_team_assignments_assigned_by_idx
  on public.project_team_assignments(assigned_by);

drop policy if exists project_team_assignments_read on public.project_team_assignments;
drop policy if exists project_team_assignments_manage on public.project_team_assignments;
drop policy if exists project_team_assignments_insert on public.project_team_assignments;
drop policy if exists project_team_assignments_update on public.project_team_assignments;
drop policy if exists project_team_assignments_delete on public.project_team_assignments;

create policy project_team_assignments_read on public.project_team_assignments
for select to authenticated
using (
  exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.active)
  and exists (select 1 from public.projects pr where pr.id=project_id and pr.deleted_at is null)
);

create policy project_team_assignments_insert on public.project_team_assignments
for insert to authenticated
with check (
  exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id=p.id where p.id=(select auth.uid()) and p.active and ur.role in ('admin','operational_supervisor','operational_manager','coordinator'))
  and exists (select 1 from public.profiles target where target.id=user_id and target.active)
  and exists (select 1 from public.projects pr where pr.id=project_id and pr.deleted_at is null)
);

create policy project_team_assignments_update on public.project_team_assignments
for update to authenticated
using (exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id=p.id where p.id=(select auth.uid()) and p.active and ur.role in ('admin','operational_supervisor','operational_manager','coordinator')))
with check (
  exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id=p.id where p.id=(select auth.uid()) and p.active and ur.role in ('admin','operational_supervisor','operational_manager','coordinator'))
  and exists (select 1 from public.profiles target where target.id=user_id and target.active)
  and exists (select 1 from public.projects pr where pr.id=project_id and pr.deleted_at is null)
);

create policy project_team_assignments_delete on public.project_team_assignments
for delete to authenticated
using (exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id=p.id where p.id=(select auth.uid()) and p.active and ur.role in ('admin','operational_supervisor','operational_manager','coordinator')));
