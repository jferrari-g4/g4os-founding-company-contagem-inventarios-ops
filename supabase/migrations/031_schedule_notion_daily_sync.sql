-- Agenda a importação do Notion diariamente às 08:00 de Brasília (11:00 UTC).
-- O segredo é gerado dentro do Postgres, fica em texto claro somente no Vault
-- e a Edge Function valida apenas seu SHA-256.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

create table if not exists public.notion_sync_credentials (
  id uuid primary key default gen_random_uuid(),
  secret_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);

alter table public.notion_sync_credentials enable row level security;
revoke all on public.notion_sync_credentials from public,anon,authenticated;

create or replace function private.rotate_notion_sync_secret()
returns void
language plpgsql
security definer
set search_path=public,private,vault,pg_catalog
as $$
declare
  v_secret text := encode(extensions.gen_random_bytes(32),'hex');
  v_vault_id uuid;
begin
  update public.notion_sync_credentials set active=false,rotated_at=now() where active=true;
  insert into public.notion_sync_credentials(secret_hash,active)
  values(encode(extensions.digest(v_secret,'sha256'),'hex'),true);

  select id into v_vault_id from vault.secrets where name='notion_sync_secret' limit 1;
  if v_vault_id is null then
    perform vault.create_secret(v_secret,'notion_sync_secret','Segredo interno do cron Notion → Contagem OPS');
  else
    perform vault.update_secret(v_vault_id,v_secret,'notion_sync_secret','Segredo interno do cron Notion → Contagem OPS');
  end if;
end;
$$;

revoke all on function private.rotate_notion_sync_secret() from public,anon,authenticated;
grant execute on function private.rotate_notion_sync_secret() to service_role;

select private.rotate_notion_sync_secret();

select cron.unschedule(jobid)
from cron.job
where jobname='notion-daily-sync-0800-brt';

select cron.schedule(
  'notion-daily-sync-0800-brt',
  '0 11 * * *',
  $cron$
  select net.http_post(
    url := 'https://racxkiswyjilfnzwmzqb.supabase.co/functions/v1/notion-daily-sync',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='notion_sync_secret' limit 1)
    ),
    body := jsonb_build_object('max_pages_per_source',10),
    timeout_milliseconds := 120000
  );
  $cron$
);

comment on table public.notion_sync_credentials is 'Somente hashes das credenciais internas do cron; o valor fica no Supabase Vault.';
