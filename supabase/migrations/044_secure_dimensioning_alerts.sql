-- Credencial server-side sem service_role na Vercel.
create table if not exists public.internal_api_credentials (
  name text primary key,
  secret_hash text not null check (secret_hash ~ '^[a-f0-9]{64}$'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);
alter table public.internal_api_credentials enable row level security;
revoke all on public.internal_api_credentials from public, anon, authenticated;
grant select on public.internal_api_credentials to service_role;
insert into public.internal_api_credentials(name,secret_hash,active)
values('dimensioning-alerts','19457aa33a226af48d6546f38fbd6287ff5a0c121ae539bdb94995093eeaa7d9',true)
on conflict(name) do update set secret_hash=excluded.secret_hash,active=true,rotated_at=now();
