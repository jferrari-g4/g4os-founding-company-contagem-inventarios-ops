-- Ordem configurável dos blocos do planejamento
-- Mudança consolidada em 06 set 2026: equipamentos vêm antes da pré-contagem.
create table public.planning_block_definitions (
  id uuid primary key default gen_random_uuid(),
  block_key text not null unique,
  label text not null,
  description text,
  sort_order integer not null unique,
  required_for_completion boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.planning_block_definitions enable row level security;
create trigger planning_block_definitions_updated before update on public.planning_block_definitions for each row execute procedure public.set_updated_at();
create policy planning_block_definitions_read on public.planning_block_definitions for select using (public.is_authenticated());
create policy planning_block_definitions_admin_manage on public.planning_block_definitions for all using (public.is_admin()) with check (public.is_admin());
