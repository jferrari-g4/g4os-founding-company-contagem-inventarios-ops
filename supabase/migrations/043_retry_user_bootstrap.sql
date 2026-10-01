-- Retry controlado para o terceiro convite quando o limite de e-mails do Auth liberar.

create or replace function public.finish_contagem_user_bootstrap(p_credential_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id bigint;
begin
  update public.contagem_user_bootstrap_credentials
     set active = false, used_at = now()
   where id = p_credential_id and active = true;

  select jobid into v_job_id
    from cron.job
   where jobname = 'contagem-user-bootstrap-retry'
   limit 1;
  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;
end;
$$;

revoke all on function public.finish_contagem_user_bootstrap(uuid) from public, anon, authenticated;
grant execute on function public.finish_contagem_user_bootstrap(uuid) to service_role;

create or replace function private.invoke_contagem_user_bootstrap_if_active()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id bigint;
begin
  if not exists (select 1 from public.contagem_user_bootstrap_credentials where active = true) then
    return null;
  end if;

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
  ) into v_request_id;
  return v_request_id;
end;
$$;

revoke all on function private.invoke_contagem_user_bootstrap_if_active() from public, anon, authenticated;
grant execute on function private.invoke_contagem_user_bootstrap_if_active() to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'contagem-user-bootstrap-retry';

select cron.schedule(
  'contagem-user-bootstrap-retry',
  '10 * * * *',
  $cron$select private.invoke_contagem_user_bootstrap_if_active();$cron$
);

comment on function public.finish_contagem_user_bootstrap(uuid) is 'Consome a credencial de bootstrap e remove o retry após os três usuários serem confirmados.';
