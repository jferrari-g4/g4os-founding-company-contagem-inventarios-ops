-- Refinamento de permissões: executar após 002_full_operational_model.sql

create or replace function public.has_role(required_role public.app_role) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.user_roles where user_id=auth.uid() and role=required_role)
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select public.has_role('admin') $$;

alter table public.integration_outbox enable row level security;

-- Cadastro de usuários e papéis: somente o próprio usuário lê o seu perfil; administração gere todos.
drop policy if exists authenticated_read_profiles on public.profiles;
drop policy if exists authenticated_write_profiles on public.profiles;
create policy profiles_read_own_or_admin on public.profiles for select using (id=auth.uid() or public.is_admin());
create policy profiles_update_own_or_admin on public.profiles for update using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());
drop policy if exists authenticated_read_user_roles on public.user_roles;
drop policy if exists authenticated_write_user_roles on public.user_roles;
create policy roles_read_own_or_admin on public.user_roles for select using (user_id=auth.uid() or public.is_admin());
create policy roles_admin_manage on public.user_roles for all using (public.is_admin()) with check (public.is_admin());

-- Configurações e catálogo só podem ser alterados por administradores.
drop policy if exists authenticated_write_custom_fields on public.custom_fields;
create policy custom_fields_admin_manage on public.custom_fields for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists authenticated_write_equipment_catalog on public.equipment_catalog;
create policy equipment_catalog_admin_manage on public.equipment_catalog for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists authenticated_write_checklist_templates on public.checklist_templates;
drop policy if exists authenticated_write_checklist_template_items on public.checklist_template_items;
create policy checklist_templates_admin_manage on public.checklist_templates for all using (public.is_admin()) with check (public.is_admin());
create policy checklist_template_items_admin_manage on public.checklist_template_items for all using (public.is_admin()) with check (public.is_admin());

-- A auditoria não pode ser alterada pelo usuário final.
drop policy if exists authenticated_write_audit_logs on public.audit_logs;
drop policy if exists authenticated_read_audit_logs on public.audit_logs;
create policy audit_read_operations on public.audit_logs for select using (public.has_role('admin') or public.has_role('operational_supervisor') or public.has_role('operational_manager'));

-- A fila de integração é acessível exclusivamente por service_role / função de backend, sem policy de usuário.
