-- Sincronização segura e idempotente do legado operacional do Notion.
-- O espelho armazena somente propriedades sanitizadas pela Edge Function.

create table if not exists public.notion_sync_sources (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  title text not null,
  database_id text not null,
  data_source_id text,
  target_kind text not null check (target_kind in ('operations','clients','task_templates','project_tasks','equipment','documents','payments')),
  enabled boolean not null default true,
  import_pii boolean not null default false,
  last_successful_sync_at timestamptz,
  last_attempted_sync_at timestamptz,
  resume_cursor text,
  resume_mode text check (resume_mode is null or resume_mode in ('full','incremental')),
  resume_since timestamptz,
  full_sync_completed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notion_sync_runs (
  id uuid primary key default gen_random_uuid(),
  trigger_kind text not null default 'scheduled' check (trigger_kind in ('scheduled','manual','dry_run')),
  status text not null default 'running' check (status in ('running','success','partial','failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  sources_total integer not null default 0,
  sources_succeeded integer not null default 0,
  sources_failed integer not null default 0,
  records_seen integer not null default 0,
  records_upserted integer not null default 0,
  materialized integer not null default 0,
  summary jsonb not null default '{}'::jsonb,
  error text
);

create table if not exists public.notion_import_records (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.notion_sync_sources(id) on delete cascade,
  notion_page_id text not null,
  notion_url text,
  title text,
  properties jsonb not null default '{}'::jsonb,
  notion_created_at timestamptz,
  notion_last_edited_at timestamptz,
  archived boolean not null default false,
  in_trash boolean not null default false,
  first_imported_at timestamptz not null default now(),
  last_imported_at timestamptz not null default now(),
  unique(source_id,notion_page_id)
);

create index if not exists notion_import_records_source_edited_idx
  on public.notion_import_records(source_id,notion_last_edited_at desc);
create index if not exists notion_sync_runs_started_idx
  on public.notion_sync_runs(started_at desc);

create table if not exists public.notion_resources (
  id uuid primary key default gen_random_uuid(),
  notion_page_id text not null unique,
  resource_type text not null,
  code text,
  name text not null,
  base text,
  available boolean,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  notion_url text,
  notion_last_edited_at timestamptz,
  synced_at timestamptz not null default now()
);

create index if not exists notion_resources_type_base_idx
  on public.notion_resources(resource_type,base,active);

create table if not exists public.notion_documents (
  id uuid primary key default gen_random_uuid(),
  notion_page_id text not null unique,
  source_kind text not null,
  title text not null,
  status text,
  category text,
  document_url text,
  metadata jsonb not null default '{}'::jsonb,
  notion_url text,
  notion_last_edited_at timestamptz,
  synced_at timestamptz not null default now()
);

create index if not exists notion_documents_kind_status_idx
  on public.notion_documents(source_kind,status);

alter table public.clients add column if not exists notion_page_id text;
alter table public.clients add column if not exists notion_last_edited_at timestamptz;
alter table public.projects add column if not exists notion_page_id text;
alter table public.projects add column if not exists notion_reference text;
alter table public.projects add column if not exists notion_client_page_id text;
alter table public.projects add column if not exists notion_last_edited_at timestamptz;
alter table public.projects add column if not exists notion_url text;
alter table public.task_templates add column if not exists notion_page_id text;
alter table public.task_templates add column if not exists notion_task_code text;
alter table public.task_templates add column if not exists notion_last_edited_at timestamptz;
alter table public.project_tasks add column if not exists notion_page_id text;
alter table public.project_tasks add column if not exists notion_last_edited_at timestamptz;
alter table public.equipment_catalog add column if not exists notion_page_id text;
alter table public.equipment_catalog add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.equipment_catalog add column if not exists notion_last_edited_at timestamptz;

create unique index if not exists clients_notion_page_uidx on public.clients(notion_page_id);
create unique index if not exists projects_notion_page_uidx on public.projects(notion_page_id);
create unique index if not exists task_templates_notion_page_uidx on public.task_templates(notion_page_id);
create unique index if not exists project_tasks_notion_page_uidx on public.project_tasks(notion_page_id);
create unique index if not exists equipment_catalog_notion_page_uidx on public.equipment_catalog(notion_page_id);

insert into public.notion_sync_sources(source_key,title,database_id,target_kind,enabled,import_pii)
values
  ('agendamento','Agendamento','19fb6feb-2e2c-8070-aca4-fddccf9a123f','operations',true,false),
  ('cadastro_clientes','Cadastro Cliente','198b6feb-2e2c-809e-b619-ccd0eaea265f','clients',true,false),
  ('tarefas','Tarefas','216b6feb-2e2c-8025-a109-db4f8ac542d9','task_templates',true,false),
  ('tarefas_em_desenvolvimento','Em Desenvolvimento','214b6feb-2e2c-806f-a389-eea5e13657ae','project_tasks',true,false),
  ('coletores','Coletores','1c1b6feb-2e2c-8097-8bb5-dda873de3835','equipment',true,false),
  ('pops','BD_Desen_POP','250b6feb-2e2c-8063-9024-d7b90dfcf760','documents',true,false),
  ('processos_internos','Processos Internos','270b6feb-2e2c-80d4-9abf-d492f2a15cf0','documents',true,false),
  ('pagamento_mo','Pagamento de MO','33ab6feb-2e2c-8080-891d-ea0d90b7c728','payments',true,false)
on conflict(source_key) do update set
  title=excluded.title,
  database_id=excluded.database_id,
  target_kind=excluded.target_kind,
  enabled=excluded.enabled,
  import_pii=excluded.import_pii,
  updated_at=now();

alter table public.notion_sync_sources enable row level security;
alter table public.notion_sync_runs enable row level security;
alter table public.notion_import_records enable row level security;
alter table public.notion_resources enable row level security;
alter table public.notion_documents enable row level security;

drop policy if exists notion_sync_sources_read on public.notion_sync_sources;
create policy notion_sync_sources_read on public.notion_sync_sources for select to authenticated
using (private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));

drop policy if exists notion_sync_runs_read on public.notion_sync_runs;
create policy notion_sync_runs_read on public.notion_sync_runs for select to authenticated
using (private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));

drop policy if exists notion_import_records_read on public.notion_import_records;
create policy notion_import_records_read on public.notion_import_records for select to authenticated
using (private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));

drop policy if exists notion_resources_read on public.notion_resources;
create policy notion_resources_read on public.notion_resources for select to authenticated using (true);

drop policy if exists notion_documents_read on public.notion_documents;
create policy notion_documents_read on public.notion_documents for select to authenticated using (true);

revoke insert,update,delete on public.notion_sync_sources from anon,authenticated;
revoke insert,update,delete on public.notion_sync_runs from anon,authenticated;
revoke insert,update,delete on public.notion_import_records from anon,authenticated;
revoke insert,update,delete on public.notion_resources from anon,authenticated;
revoke insert,update,delete on public.notion_documents from anon,authenticated;
grant select on public.notion_sync_sources,public.notion_sync_runs,public.notion_import_records,public.notion_resources,public.notion_documents to authenticated;

comment on table public.notion_import_records is 'Espelho sanitizado do Notion; nunca deve conter senhas, tokens, CPF ou RG.';
comment on column public.notion_sync_sources.import_pii is 'Permanece false por padrão. PII exige decisão e controles específicos.';
