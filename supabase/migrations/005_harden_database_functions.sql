-- Endurecimento de funções e permissões internas.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.has_role(required_role public.app_role) returns boolean language sql stable security definer set search_path=public,pg_catalog as $$
  select exists(select 1 from public.user_roles where user_id=auth.uid() and role=required_role)
$$;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path=public,pg_catalog as $$ select private.has_role('admin') $$;

-- Políticas administrativas passam a usar funções do schema privado.
alter policy profiles_read_own_or_admin on public.profiles using (id=auth.uid() or private.is_admin());
alter policy profiles_update_own_or_admin on public.profiles using (id=auth.uid() or private.is_admin()) with check (id=auth.uid() or private.is_admin());
alter policy roles_read_own_or_admin on public.user_roles using (user_id=auth.uid() or private.is_admin());
alter policy roles_admin_manage on public.user_roles using (private.is_admin()) with check (private.is_admin());
alter policy custom_fields_admin_manage on public.custom_fields using (private.is_admin()) with check (private.is_admin());
alter policy equipment_catalog_admin_manage on public.equipment_catalog using (private.is_admin()) with check (private.is_admin());
alter policy checklist_templates_admin_manage on public.checklist_templates using (private.is_admin()) with check (private.is_admin());
alter policy checklist_template_items_admin_manage on public.checklist_template_items using (private.is_admin()) with check (private.is_admin());
alter policy audit_read_operations on public.audit_logs using (private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager'));
alter policy planning_block_definitions_admin_manage on public.planning_block_definitions using (private.is_admin()) with check (private.is_admin());

-- Fixar search_path de funções públicas não privilegiadas.
alter function public.set_updated_at() set search_path = public,pg_catalog;
alter function public.is_authenticated() set search_path = public,pg_catalog;

-- Funções de trigger e rotinas internas não ficam expostas por RPC.
revoke all on function public.audit_row() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.queue_project_notification() from public, anon, authenticated;
revoke all on function public.overdue_dimensionings() from public, anon, authenticated;
revoke all on function public.has_role(public.app_role) from public, anon, authenticated;
revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.overdue_dimensionings() to service_role;
