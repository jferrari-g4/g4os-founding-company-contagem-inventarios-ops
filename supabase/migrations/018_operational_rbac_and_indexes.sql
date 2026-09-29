-- Fecha bypasses de escrita por usuário autenticado e remove sobreposição nas policies novas.

-- Clientes e contatos: comercial/operação; exclusão somente admin.
drop policy if exists authenticated_write_clients on public.clients;
drop policy if exists clients_operational_insert on public.clients;
drop policy if exists clients_operational_update on public.clients;
drop policy if exists clients_admin_delete on public.clients;
create policy clients_operational_insert on public.clients for insert to authenticated with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy clients_operational_update on public.clients for update to authenticated using (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
) with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy clients_admin_delete on public.clients for delete to authenticated using (private.has_role('admin'));

drop policy if exists authenticated_write_client_contacts on public.client_contacts;
drop policy if exists client_contacts_operational_insert on public.client_contacts;
drop policy if exists client_contacts_operational_update on public.client_contacts;
drop policy if exists client_contacts_admin_delete on public.client_contacts;
create policy client_contacts_operational_insert on public.client_contacts for insert to authenticated with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy client_contacts_operational_update on public.client_contacts for update to authenticated using (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
) with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy client_contacts_admin_delete on public.client_contacts for delete to authenticated using (private.has_role('admin'));

-- Projetos e valores configuráveis.
drop policy if exists projects_insert_open on public.projects;
drop policy if exists projects_update_open on public.projects;
drop policy if exists projects_delete_admin on public.projects;
create policy projects_insert_open on public.projects for insert to authenticated with check (
  status<>'confirmed' and (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
);
create policy projects_update_open on public.projects for update to authenticated using (
  status<>'confirmed' and (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('ti'))
) with check (
  status<>'confirmed' and (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('ti'))
);
create policy projects_delete_admin on public.projects for delete to authenticated using (private.has_role('admin') and status<>'confirmed');

drop policy if exists authenticated_write_project_field_values on public.project_field_values;
drop policy if exists project_field_values_operational_insert on public.project_field_values;
drop policy if exists project_field_values_operational_update on public.project_field_values;
drop policy if exists project_field_values_admin_delete on public.project_field_values;
create policy project_field_values_operational_insert on public.project_field_values for insert to authenticated with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy project_field_values_operational_update on public.project_field_values for update to authenticated using (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
) with check (
  private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy project_field_values_admin_delete on public.project_field_values for delete to authenticated using (private.has_role('admin'));

-- Dimensionamento e datas: somente operação; gates finais continuam obrigatoriamente via RPC/trigger.
do $$
declare t text;
begin
  foreach t in array array['date_options','dimensionings','dimensioning_options'] loop
    execute format('drop policy if exists authenticated_write_%1$s on public.%1$s',t);
    execute format('drop policy if exists %1$s_operational_insert on public.%1$s',t);
    execute format('drop policy if exists %1$s_operational_update on public.%1$s',t);
    execute format('drop policy if exists %1$s_admin_delete on public.%1$s',t);
    execute format($policy$create policy %1$s_operational_insert on public.%1$s for insert to authenticated with check (
      private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
    )$policy$,t);
    execute format($policy$create policy %1$s_operational_update on public.%1$s for update to authenticated using (
      private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
    ) with check (
      private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
    )$policy$,t);
    execute format('create policy %1$s_admin_delete on public.%1$s for delete to authenticated using (private.has_role(''admin''))',t);
  end loop;
end $$;

-- TI: somente TI e gestores autorizados.
drop policy if exists authenticated_write_ti_validations on public.ti_validations;
drop policy if exists ti_validations_authorized_insert on public.ti_validations;
drop policy if exists ti_validations_authorized_update on public.ti_validations;
drop policy if exists ti_validations_admin_delete on public.ti_validations;
create policy ti_validations_authorized_insert on public.ti_validations for insert to authenticated with check (
  private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy ti_validations_authorized_update on public.ti_validations for update to authenticated using (
  private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
) with check (
  private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager')
);
create policy ti_validations_admin_delete on public.ti_validations for delete to authenticated using (private.has_role('admin'));

-- Rascunhos de planejamento: perfis de criação/planejamento; aprovação segue RPC protegida.
drop policy if exists planning_insert_draft on public.plannings;
drop policy if exists planning_update_draft on public.plannings;
create policy planning_insert_draft on public.plannings for insert to authenticated with check (
  status in ('draft','in_progress','awaiting_checklists','awaiting_approval') and
  (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
);
create policy planning_update_draft on public.plannings for update to authenticated using (
  status in ('draft','in_progress','awaiting_checklists','awaiting_approval') and
  (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
) with check (
  status in ('draft','in_progress','awaiting_checklists','awaiting_approval') and
  (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
);

-- Remove SELECT duplicado das policies FOR ALL das tabelas novas.
drop policy if exists task_templates_admin_write on public.task_templates;
drop policy if exists task_templates_admin_insert on public.task_templates;
drop policy if exists task_templates_admin_update on public.task_templates;
drop policy if exists task_templates_admin_delete on public.task_templates;
create policy task_templates_admin_insert on public.task_templates for insert to authenticated with check (private.has_role('admin'));
create policy task_templates_admin_update on public.task_templates for update to authenticated using (private.has_role('admin')) with check (private.has_role('admin'));
create policy task_templates_admin_delete on public.task_templates for delete to authenticated using (private.has_role('admin'));

drop policy if exists project_tasks_operational_write on public.project_tasks;
drop policy if exists project_tasks_operational_insert on public.project_tasks;
drop policy if exists project_tasks_operational_update on public.project_tasks;
drop policy if exists project_tasks_admin_delete on public.project_tasks;
create policy project_tasks_operational_insert on public.project_tasks for insert to authenticated with check (
  private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('coordinator')
);
create policy project_tasks_operational_update on public.project_tasks for update to authenticated using (
  private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('coordinator')
) with check (
  private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager') or private.has_role('coordinator')
);
create policy project_tasks_admin_delete on public.project_tasks for delete to authenticated using (private.has_role('admin'));

-- Índices que cobrem os FKs usados nos novos fluxos.
create index if not exists dimensioning_options_dimensioning_idx on public.dimensioning_options(dimensioning_id);
create index if not exists project_tasks_template_idx on public.project_tasks(template_id);
create index if not exists project_tasks_completed_by_idx on public.project_tasks(completed_by);
create index if not exists task_templates_created_by_idx on public.task_templates(created_by);
create index if not exists task_templates_updated_by_idx on public.task_templates(updated_by);
