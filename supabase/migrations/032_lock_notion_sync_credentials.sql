-- Torna explícita a negação total aos hashes de autenticação do cron.
-- A Edge Function acessa a tabela exclusivamente por service_role, que ignora RLS.

drop policy if exists notion_sync_credentials_deny on public.notion_sync_credentials;
create policy notion_sync_credentials_deny
on public.notion_sync_credentials
for all
to anon,authenticated
using (false)
with check (false);

revoke all on public.notion_sync_credentials from public,anon,authenticated;
