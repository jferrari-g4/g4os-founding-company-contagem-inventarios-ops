-- Endurece ownership, retry, concorrência, sanitização e reconciliação da integração Notion.

alter table public.clients add column if not exists notion_origin boolean not null default false;
alter table public.projects add column if not exists notion_origin boolean not null default false;
alter table public.task_templates add column if not exists notion_origin boolean not null default false;
alter table public.project_tasks add column if not exists notion_origin boolean not null default false;
alter table public.equipment_catalog add column if not exists notion_origin boolean not null default false;
alter table public.notion_import_records add column if not exists last_seen_run_id uuid references public.notion_sync_runs(id) on delete set null;
alter table public.notion_sync_sources add column if not exists checkpoint_version bigint not null default 0;

create table if not exists public.notion_entity_links (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.notion_sync_sources(id) on delete cascade,
  notion_page_id text not null,
  entity_type text not null check(entity_type in ('client','project','task_template','project_task','equipment')),
  entity_id uuid not null,
  match_strategy text not null check(match_strategy in ('created','notion_id','cnpj','reference')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id,notion_page_id,entity_type)
);
create index if not exists notion_entity_links_entity_idx on public.notion_entity_links(entity_type,entity_id);

create table if not exists public.notion_materialization_failures (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.notion_sync_sources(id) on delete cascade,
  notion_page_id text not null,
  error text not null,
  attempts integer not null default 1,
  first_failed_at timestamptz not null default now(),
  last_failed_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique(source_id,notion_page_id)
);
create index if not exists notion_materialization_failures_pending_idx on public.notion_materialization_failures(source_id,last_failed_at desc) where resolved_at is null;

create table if not exists public.notion_sync_locks (
  lock_name text primary key,
  run_id uuid not null references public.notion_sync_runs(id) on delete cascade,
  acquired_at timestamptz not null default now()
);

alter table public.notion_entity_links enable row level security;
alter table public.notion_materialization_failures enable row level security;
alter table public.notion_sync_locks enable row level security;

drop policy if exists notion_entity_links_read on public.notion_entity_links;
create policy notion_entity_links_read on public.notion_entity_links for select to authenticated
using(private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));
drop policy if exists notion_materialization_failures_read on public.notion_materialization_failures;
create policy notion_materialization_failures_read on public.notion_materialization_failures for select to authenticated
using(private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));
drop policy if exists notion_sync_locks_deny on public.notion_sync_locks;
create policy notion_sync_locks_deny on public.notion_sync_locks for all to anon,authenticated using(false) with check(false);

revoke insert,update,delete on public.notion_entity_links,public.notion_materialization_failures from anon,authenticated;
revoke all on public.notion_sync_locks from public,anon,authenticated;
grant select on public.notion_entity_links,public.notion_materialization_failures to authenticated;

-- Documentos e recursos importados podem conter metadados operacionais: leitura só gerencial.
drop policy if exists notion_resources_read on public.notion_resources;
create policy notion_resources_read on public.notion_resources for select to authenticated
using(private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));
drop policy if exists notion_documents_read on public.notion_documents;
create policy notion_documents_read on public.notion_documents for select to authenticated
using(private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));

-- Pagamentos ficam fora da carga até existir destino e revisão específica de dados financeiros.
update public.notion_sync_sources set enabled=false,last_error='Fonte desabilitada: destino financeiro e allowlist pendentes.',updated_at=now()
where source_key='pagamento_mo';

-- Operações legadas importadas não devem disparar notificações de nova solicitação.
create or replace function public.queue_project_notification()
returns trigger language plpgsql security definer set search_path=public,pg_catalog as $$
begin
  if coalesce(new.notion_origin,false) then return new; end if;
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

-- Mantém o job suspenso até o NOTION_TOKEN passar por dry-run validado.
select cron.unschedule(jobid) from cron.job where jobname='notion-daily-sync-0800-brt';

comment on table public.notion_entity_links is 'Reconciliação explícita: vínculo não concede ownership ao Notion.';
comment on table public.notion_materialization_failures is 'Dead-letter auditável; falhas impedem avanço do cursor da página.';
