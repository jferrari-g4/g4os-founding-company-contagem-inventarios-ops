-- Bootstrap interno e de uso único para convites administrativos.
-- O segredo nasce no Postgres, fica no Vault e nunca é exposto ao cliente.

create table if not exists public.contagem_user_bootstrap_credentials (
  id uuid primary key default gen_random_uuid(),
  secret_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  used_at timestamptz
);

alter table public.contagem_user_bootstrap_credentials enable row level security;
revoke all on public.contagem_user_bootstrap_credentials from public, anon, authenticated;
grant select, update on public.contagem_user_bootstrap_credentials to service_role;

create or replace function private.rotate_contagem_user_bootstrap_secret()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text := encode(extensions.gen_random_bytes(32), 'hex');
  v_vault_id uuid;
begin
  update public.contagem_user_bootstrap_credentials
     set active = false, used_at = coalesce(used_at, now())
   where active = true;

  insert into public.contagem_user_bootstrap_credentials(secret_hash, active)
  values (encode(extensions.digest(v_secret, 'sha256'), 'hex'), true);

  select id into v_vault_id
    from vault.secrets
   where name = 'contagem_user_bootstrap_secret'
   limit 1;

  if v_vault_id is null then
    perform vault.create_secret(v_secret, 'contagem_user_bootstrap_secret', 'Segredo de uso único para bootstrap dos usuários da Contagem OPS');
  else
    perform vault.update_secret(v_vault_id, v_secret, 'contagem_user_bootstrap_secret', 'Segredo de uso único para bootstrap dos usuários da Contagem OPS');
  end if;
end;
$$;

revoke all on function private.rotate_contagem_user_bootstrap_secret() from public, anon, authenticated;
grant execute on function private.rotate_contagem_user_bootstrap_secret() to service_role;

create or replace function private.invoke_contagem_user_bootstrap()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select net.http_post(
    url := 'https://racxkiswyjilfnzwmzqb.supabase.co/functions/v1/contagem-user-bootstrap',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-bootstrap-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'contagem_user_bootstrap_secret' limit 1)
    ),
    body := jsonb_build_object(
      'emails', jsonb_build_array(
        'balbino@contageminventarios.com.br',
        'estoque@contandoporvoce.com.br',
        'simonsen@contandoporvoce.com.br'
      )
    ),
    timeout_milliseconds := 120000
  );
$$;

revoke all on function private.invoke_contagem_user_bootstrap() from public, anon, authenticated;
grant execute on function private.invoke_contagem_user_bootstrap() to service_role;

select private.rotate_contagem_user_bootstrap_secret();

comment on table public.contagem_user_bootstrap_credentials is 'Hashes de credenciais internas de uso único; o valor fica somente no Supabase Vault.';
comment on function private.invoke_contagem_user_bootstrap() is 'Dispara via pg_net o lote fechado dos três administradores aprovados.';
