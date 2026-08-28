-- Contagem Ops: modelo operacional completo
-- Executar depois de 001_initial_schema.sql

-- Papéis e usuários
create type public.app_role as enum ('admin','commercial','operational_supervisor','operational_manager','operational','ti','coordinator','viewer');
create type public.commercial_status as enum ('open','won','lost','cancelled');
create type public.dimensioning_status as enum ('open','in_progress','awaiting_approval','approved','rejected');
create type public.ti_validation_status as enum ('not_required','pending','approved','rejected');
create type public.planning_status as enum ('draft','in_progress','awaiting_checklists','awaiting_approval','approved','published','cancelled');
create type public.checklist_status as enum ('not_started','in_progress','completed','waived');
create type public.notification_channel as enum ('email','slack');
create type public.notification_status as enum ('pending','processing','sent','failed','cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  primary key (user_id, role)
);

-- Cadastro operacional e solicitações
alter table public.clients add column if not exists cnpj_raw text;
alter table public.clients add column if not exists cnpj_data jsonb not null default '{}'::jsonb;
alter table public.clients add column if not exists erp_external_id text;
alter table public.clients add column if not exists updated_at timestamptz not null default now();
alter table public.projects add column if not exists commercial_status public.commercial_status not null default 'open';
alter table public.projects add column if not exists selected_date_option_id uuid;
alter table public.projects add column if not exists priority_score integer not null default 0;
alter table public.projects add column if not exists requested_at timestamptz not null default now();
alter table public.projects add column if not exists commercial_closed_at timestamptz;
alter table public.projects add column if not exists operational_notes text;
alter table public.projects add column if not exists updated_by uuid references public.profiles(id);
alter table public.projects add column if not exists deleted_at timestamptz;
alter table public.date_options add column if not exists ends_at timestamptz;
alter table public.date_options add column if not exists sent_at timestamptz;
alter table public.date_options add column if not exists selected_at timestamptz;
alter table public.date_options add column if not exists selected_by uuid references public.profiles(id);
alter table public.dimensionings alter column status drop default;
alter table public.dimensionings alter column status type public.dimensioning_status using status::public.dimensioning_status;
alter table public.dimensionings alter column status set default 'open';
alter table public.dimensionings add column if not exists due_at timestamptz;
alter table public.dimensionings add column if not exists approved_by uuid references public.profiles(id);
alter table public.dimensionings add column if not exists approved_at timestamptz;
alter table public.dimensionings add column if not exists notes text;
alter table public.ti_validations alter column status drop default;
alter table public.ti_validations alter column status type public.ti_validation_status using case when status='pending' then 'pending' else 'not_required' end::public.ti_validation_status;
alter table public.ti_validations alter column status set default 'pending';
alter table public.ti_validations add column if not exists required boolean not null default true;
alter table public.ti_validations add column if not exists system_name text;
alter table public.ti_validations add column if not exists ti_contact_name text;
alter table public.ti_validations add column if not exists ti_contact_email text;
alter table public.ti_validations add column if not exists ti_contact_phone text;
alter table public.plannings alter column status drop default;
alter table public.plannings alter column status type public.planning_status using case when status='draft' then 'draft' else 'in_progress' end::public.planning_status;
alter table public.plannings alter column status set default 'draft';
alter table public.plannings add column if not exists completion_percentage numeric(5,2) not null default 0;
alter table public.plannings add column if not exists started_by uuid references public.profiles(id);
alter table public.plannings add column if not exists published_at timestamptz;
alter table public.plannings add column if not exists notion_page_id text;
alter table public.plannings add column if not exists pdf_storage_path text;

alter table public.projects add constraint projects_selected_date_option_fk foreign key (selected_date_option_id) references public.date_options(id) deferrable initially deferred;

-- Planejamento dividido em blocos, linhas e dias dinâmicos
create table public.planning_responsibilities (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  role_name text not null, person_name text, profile_id uuid references public.profiles(id), notes text, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.planning_transports (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  travel_date date not null, route text not null, passengers text, quantity integer, notes text, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.planning_accommodations (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  guests text not null, rooms text, check_in date, check_out date, guest_count integer, notes text, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.planning_pre_counts (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  work_date date not null, starts_at time, team_name text, people_count integer, notes text, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.equipment_catalog (
  id uuid primary key default gen_random_uuid(), owner_type text not null check(owner_type in ('client','contagem')), name text not null, active boolean not null default true, unique(owner_type,name)
);
create table public.planning_equipment_requirements (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  owner_type text not null check(owner_type in ('client','contagem')), equipment_id uuid references public.equipment_catalog(id), equipment_name text not null, work_date date, shift_name text, quantity integer not null default 1, status text not null default 'requested', notes text, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.planning_days (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  day_number integer not null, inventory_date date not null, expected_headcount integer, notes text, sort_order integer not null default 0, unique(planning_id,day_number)
);
create table public.planning_day_areas (
  id uuid primary key default gen_random_uuid(), planning_day_id uuid not null references public.planning_days(id) on delete cascade,
  name text not null, shift_name text, starts_at time, expected_headcount integer, notes text, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.planning_area_team_roles (
  id uuid primary key default gen_random_uuid(), area_id uuid not null references public.planning_day_areas(id) on delete cascade,
  role_name text not null, people_count integer, people_names text, sort_order integer not null default 0
);
create table public.planning_area_activities (
  id uuid primary key default gen_random_uuid(), area_id uuid not null references public.planning_day_areas(id) on delete cascade,
  activity_name text not null, notes text, sort_order integer not null default 0
);

-- Templates e execução de checklist
create table public.checklist_templates (
  id uuid primary key default gen_random_uuid(), name text not null, checklist_type text not null check(checklist_type in ('pre_inventory_visit','planning')), inventory_type text, active boolean not null default true, created_at timestamptz not null default now()
);
create table public.checklist_template_items (
  id uuid primary key default gen_random_uuid(), template_id uuid not null references public.checklist_templates(id) on delete cascade,
  label text not null, required boolean not null default true, sort_order integer not null default 0
);
create table public.planning_checklists (
  id uuid primary key default gen_random_uuid(), planning_id uuid not null references public.plannings(id) on delete cascade,
  template_id uuid references public.checklist_templates(id), checklist_type text not null check(checklist_type in ('pre_inventory_visit','planning')), due_at timestamptz, status public.checklist_status not null default 'not_started', completed_by uuid references public.profiles(id), completed_at timestamptz, unique(planning_id,checklist_type)
);
create table public.planning_checklist_items (
  id uuid primary key default gen_random_uuid(), checklist_id uuid not null references public.planning_checklists(id) on delete cascade,
  template_item_id uuid references public.checklist_template_items(id), label text not null, required boolean not null default true, completed boolean not null default false, completed_by uuid references public.profiles(id), completed_at timestamptz, owner_id uuid references public.profiles(id), notes text, evidence_path text, sort_order integer not null default 0
);

-- Integrações, arquivos, histórico e notificações assíncronas
create table public.attachments (
  id uuid primary key default gen_random_uuid(), project_id uuid references public.projects(id) on delete cascade, planning_id uuid references public.plannings(id) on delete cascade,
  storage_path text not null, file_name text not null, mime_type text, size_bytes bigint, uploaded_by uuid references public.profiles(id), created_at timestamptz not null default now(), check(project_id is not null or planning_id is not null)
);
create table public.integration_outbox (
  id uuid primary key default gen_random_uuid(), project_id uuid references public.projects(id) on delete cascade,
  channel public.notification_channel not null, event_name text not null, recipient text, payload jsonb not null default '{}'::jsonb, status public.notification_status not null default 'pending', attempts integer not null default 0, last_error text, scheduled_for timestamptz not null default now(), sent_at timestamptz, created_at timestamptz not null default now()
);
create index integration_outbox_pending_idx on public.integration_outbox(status,scheduled_for);
create index projects_status_idx on public.projects(status,requested_at);
create index dimensionings_due_idx on public.dimensionings(status,due_at);

-- Funções comuns
create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',new.email),new.email) on conflict(id) do nothing; return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create trigger profiles_updated before update on public.profiles for each row execute procedure public.set_updated_at();
create trigger clients_updated before update on public.clients for each row execute procedure public.set_updated_at();
create trigger projects_updated before update on public.projects for each row execute procedure public.set_updated_at();
create trigger plannings_updated before update on public.plannings for each row execute procedure public.set_updated_at();

create or replace function public.audit_row() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.audit_logs(entity,entity_id,action,before_data,after_data,actor_id) values(tg_table_name,coalesce(new.id,old.id),tg_op,to_jsonb(old),to_jsonb(new),auth.uid()); return coalesce(new,old); end $$;
create trigger projects_audit after insert or update or delete on public.projects for each row execute procedure public.audit_row();
create trigger plannings_audit after insert or update or delete on public.plannings for each row execute procedure public.audit_row();
create trigger dimensionings_audit after insert or update or delete on public.dimensionings for each row execute procedure public.audit_row();

create or replace function public.queue_project_notification() returns trigger language plpgsql security definer set search_path=public as $$ begin
  if tg_op='INSERT' then insert into public.integration_outbox(project_id,channel,event_name,payload) values(new.id,'email','project_opened',jsonb_build_object('reference',new.reference)),(new.id,'slack','project_opened',jsonb_build_object('reference',new.reference)); end if;
  if tg_op='UPDATE' and new.status='confirmed' and old.status is distinct from new.status then insert into public.integration_outbox(project_id,channel,event_name,payload) values(new.id,'email','project_confirmed',jsonb_build_object('reference',new.reference)),(new.id,'slack','project_confirmed',jsonb_build_object('reference',new.reference)); end if;
  return new;
end $$;
create trigger projects_notification_queue after insert or update on public.projects for each row execute procedure public.queue_project_notification();

-- Consulta usada por Cron Vercel, Edge Function ou n8n para alerta após 24h
create or replace function public.overdue_dimensionings() returns table(project_id uuid, reference text, client_name text, opened_at timestamptz, due_at timestamptz) language sql security definer set search_path=public as $$
 select p.id,p.reference,c.legal_name,d.opened_at,d.due_at from public.dimensionings d join public.projects p on p.id=d.project_id join public.clients c on c.id=p.client_id where d.status in ('open','in_progress') and coalesce(d.due_at,d.opened_at+interval '24 hours') <= now();
$$;

-- RLS: acesso restrito a usuários autenticados; detalhamento por papel pode ser refinado depois do piloto.
alter table public.profiles enable row level security; alter table public.user_roles enable row level security;
alter table public.planning_responsibilities enable row level security; alter table public.planning_transports enable row level security; alter table public.planning_accommodations enable row level security; alter table public.planning_pre_counts enable row level security; alter table public.equipment_catalog enable row level security; alter table public.planning_equipment_requirements enable row level security; alter table public.planning_days enable row level security; alter table public.planning_day_areas enable row level security; alter table public.planning_area_team_roles enable row level security; alter table public.planning_area_activities enable row level security; alter table public.checklist_templates enable row level security; alter table public.checklist_template_items enable row level security; alter table public.planning_checklists enable row level security; alter table public.planning_checklist_items enable row level security; alter table public.attachments enable row level security; alter table public.integration_outbox enable row level security;
create or replace function public.is_authenticated() returns boolean language sql stable as $$ select auth.uid() is not null $$;
do $$ declare t text; begin foreach t in array array['clients','client_contacts','projects','custom_fields','project_field_values','date_options','dimensionings','dimensioning_options','ti_validations','plannings','audit_logs','profiles','user_roles','planning_responsibilities','planning_transports','planning_accommodations','planning_pre_counts','equipment_catalog','planning_equipment_requirements','planning_days','planning_day_areas','planning_area_team_roles','planning_area_activities','checklist_templates','checklist_template_items','planning_checklists','planning_checklist_items','attachments'] loop execute format('create policy "authenticated_read_%1$s" on public.%1$s for select using (public.is_authenticated())',t); execute format('create policy "authenticated_write_%1$s" on public.%1$s for all using (public.is_authenticated()) with check (public.is_authenticated())',t); end loop; end $$;
-- A outbox é somente backend/service-role: não criar políticas para usuários.
