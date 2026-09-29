-- Conexões individuais entre Contagem OPS e G4 OS.
-- Tokens são persistidos apenas como SHA-256 e nunca retornam após a criação.

create table if not exists public.contagem_g4os_connections (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default 'G4 OS' check (length(btrim(label)) between 1 and 80),
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  token_prefix text not null check (length(token_prefix) between 8 and 24),
  scopes jsonb not null default '["read","write"]'::jsonb check (jsonb_typeof(scopes)='array'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create unique index if not exists contagem_g4os_one_active_connection_per_user on public.contagem_g4os_connections(owner_user_id) where active;
create index if not exists contagem_g4os_connections_owner_idx on public.contagem_g4os_connections(owner_user_id,created_at desc);

create table if not exists public.contagem_g4os_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  connection_id uuid references public.contagem_g4os_connections(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  tool_name text not null check (length(btrim(tool_name)) between 1 and 120),
  operation text not null check (operation in ('READ','WRITE','AUTH','ERROR')),
  success boolean not null,
  request_id text,
  duration_ms integer check (duration_ms is null or duration_ms>=0),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details)='object')
);
create index if not exists contagem_g4os_events_owner_idx on public.contagem_g4os_events(actor_user_id,occurred_at desc);

alter table public.contagem_g4os_connections enable row level security;
alter table public.contagem_g4os_events enable row level security;
revoke all on public.contagem_g4os_connections,public.contagem_g4os_events from anon,authenticated;
grant select on public.contagem_g4os_connections,public.contagem_g4os_events to authenticated;

drop policy if exists contagem_g4os_connections_read_own on public.contagem_g4os_connections;
create policy contagem_g4os_connections_read_own on public.contagem_g4os_connections for select to authenticated using (owner_user_id=auth.uid() or private.is_admin());
drop policy if exists contagem_g4os_events_read_own on public.contagem_g4os_events;
create policy contagem_g4os_events_read_own on public.contagem_g4os_events for select to authenticated using (actor_user_id=auth.uid() or private.is_admin());
