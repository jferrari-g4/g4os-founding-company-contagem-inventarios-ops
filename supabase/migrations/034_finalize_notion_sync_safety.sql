-- Fecha consistência de full sync paginado e mantém o cron suspenso até dry-run com token válido.

alter table public.notion_sync_sources add column if not exists resume_started_at timestamptz;

-- Suprime somente a notificação de criação do legado; futuras confirmações humanas continuam notificando.
create or replace function public.queue_project_notification()
returns trigger language plpgsql security definer set search_path=public,pg_catalog as $$
begin
  if tg_op='INSERT' and coalesce(new.notion_origin,false) then return new; end if;
  if tg_op='INSERT' then
    insert into public.integration_outbox(project_id,channel,event_name,payload)
    values(new.id,'email','project_opened',jsonb_build_object('reference',new.reference)),
          (new.id,'slack','project_opened',jsonb_build_object('reference',new.reference));
  end if;
  if tg_op='UPDATE' and new.status='confirmed' and old.status is distinct from new.status then
    insert into public.integration_outbox(project_id,channel,event_name,payload)
    values(new.id,'email','project_confirmed',jsonb_build_object('reference',new.reference)),
          (new.id,'slack','project_confirmed',jsonb_build_object('reference',new.reference));
  end if;
  return new;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname='notion-daily-sync-0800-brt';

create or replace function private.enable_notion_sync_schedule()
returns bigint
language plpgsql
security definer
set search_path=public,private,vault,cron,net,pg_catalog
as $$
declare v_job_id bigint;
begin
  perform cron.unschedule(jobid) from cron.job where jobname='notion-daily-sync-0800-brt';
  select cron.schedule(
    'notion-daily-sync-0800-brt','0 11 * * *',
    $cron$
    select net.http_post(
      url := 'https://racxkiswyjilfnzwmzqb.supabase.co/functions/v1/notion-daily-sync',
      headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='notion_sync_secret' limit 1)),
      body := jsonb_build_object('max_pages_per_source',10,'full',extract(isodow from timezone('America/Sao_Paulo',now()))=7),
      timeout_milliseconds := 120000
    );
    $cron$
  ) into v_job_id;
  return v_job_id;
end;
$$;
revoke all on function private.enable_notion_sync_schedule() from public,anon,authenticated;
grant execute on function private.enable_notion_sync_schedule() to service_role;

comment on function private.enable_notion_sync_schedule() is 'Ativar somente após NOTION_TOKEN válido e dry-run revisado.';
