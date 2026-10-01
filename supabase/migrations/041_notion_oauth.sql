-- OAuth seguro para a sincronização Notion -> Contagem OPS.
-- Tokens ficam criptografados no Supabase Vault e nunca são expostos ao frontend.

create table if not exists public.notion_oauth_states (
  state_hash text primary key,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.notion_oauth_states enable row level security;
revoke all on public.notion_oauth_states from public, anon, authenticated;
grant select, insert, delete on public.notion_oauth_states to service_role;

create table if not exists public.notion_oauth_authorizations (
  workspace_id text primary key,
  workspace_name text,
  workspace_icon text,
  bot_id text not null,
  notion_owner_id text,
  active boolean not null default true,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notion_oauth_authorizations enable row level security;
revoke all on public.notion_oauth_authorizations from public, anon, authenticated;
grant select, insert, update on public.notion_oauth_authorizations to service_role;

create or replace function public.store_notion_oauth_tokens(
  p_access_token text,
  p_refresh_token text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if nullif(p_access_token, '') is null then
    raise exception 'Access token obrigatório.';
  end if;

  select id into v_id from vault.secrets where name = 'notion_oauth_access_token' limit 1;
  if v_id is null then
    perform vault.create_secret(p_access_token, 'notion_oauth_access_token', 'OAuth access token do Contagem OPS Sync');
  else
    perform vault.update_secret(v_id, p_access_token, 'notion_oauth_access_token', 'OAuth access token do Contagem OPS Sync');
  end if;

  if nullif(p_refresh_token, '') is not null then
    select id into v_id from vault.secrets where name = 'notion_oauth_refresh_token' limit 1;
    if v_id is null then
      perform vault.create_secret(p_refresh_token, 'notion_oauth_refresh_token', 'OAuth refresh token do Contagem OPS Sync');
    else
      perform vault.update_secret(v_id, p_refresh_token, 'notion_oauth_refresh_token', 'OAuth refresh token do Contagem OPS Sync');
    end if;
  end if;
end;
$$;

revoke all on function public.store_notion_oauth_tokens(text, text) from public, anon, authenticated;
grant execute on function public.store_notion_oauth_tokens(text, text) to service_role;

create or replace function public.get_notion_oauth_tokens()
returns table(access_token text, refresh_token text)
language sql
security definer
set search_path = ''
as $$
  select
    (select decrypted_secret from vault.decrypted_secrets where name = 'notion_oauth_access_token' limit 1),
    (select decrypted_secret from vault.decrypted_secrets where name = 'notion_oauth_refresh_token' limit 1);
$$;

revoke all on function public.get_notion_oauth_tokens() from public, anon, authenticated;
grant execute on function public.get_notion_oauth_tokens() to service_role;

comment on table public.notion_oauth_states is 'Estados OAuth de uso único, armazenados somente como SHA-256 e expirados em 10 minutos.';
comment on table public.notion_oauth_authorizations is 'Metadados não secretos da autorização OAuth do Notion.';
comment on function public.store_notion_oauth_tokens(text, text) is 'Armazena ou rotaciona tokens OAuth do Notion no Supabase Vault. Somente service_role.';
comment on function public.get_notion_oauth_tokens() is 'Lê tokens OAuth do Notion exclusivamente para rotinas server-side com service_role.';
