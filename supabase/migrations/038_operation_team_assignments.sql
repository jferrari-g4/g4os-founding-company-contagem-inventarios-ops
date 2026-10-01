-- Alocação de pessoas por inventário, inspirada nas relações de Coordenadores/Equipe do Notion.
create table if not exists public.project_team_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  assignment_role text not null check (length(btrim(assignment_role)) between 1 and 120),
  team_type text not null default 'internal' check (team_type in ('internal','freelance','coordinator','support')),
  status text not null default 'planned' check (status in ('planned','invited','confirmed','declined')),
  shift text,
  area text,
  notes text,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,user_id,assignment_role)
);

create index if not exists project_team_assignments_project_idx on public.project_team_assignments(project_id,status);
create index if not exists project_team_assignments_user_idx on public.project_team_assignments(user_id);

alter table public.project_team_assignments enable row level security;

drop policy if exists project_team_assignments_read on public.project_team_assignments;
create policy project_team_assignments_read on public.project_team_assignments
for select to authenticated
using (
  exists (select 1 from public.profiles p where p.id=auth.uid() and p.active)
  and exists (select 1 from public.projects pr where pr.id=project_id and pr.deleted_at is null)
);

drop policy if exists project_team_assignments_manage on public.project_team_assignments;
create policy project_team_assignments_manage on public.project_team_assignments
for all to authenticated
using (
  exists (
    select 1 from public.profiles p
    join public.user_roles ur on ur.user_id=p.id
    where p.id=auth.uid() and p.active
      and ur.role in ('admin','operational_supervisor','operational_manager','coordinator')
  )
)
with check (
  exists (
    select 1 from public.profiles p
    join public.user_roles ur on ur.user_id=p.id
    where p.id=auth.uid() and p.active
      and ur.role in ('admin','operational_supervisor','operational_manager','coordinator')
  )
  and exists (select 1 from public.profiles target where target.id=user_id and target.active)
  and exists (select 1 from public.projects pr where pr.id=project_id and pr.deleted_at is null)
);

grant select,insert,update,delete on public.project_team_assignments to authenticated;
