-- Restringe estados de criação e torna evidências dos gates imutáveis após o avanço.

-- Uma solicitação nasce em Entrada quando exige dimensionamento ou diretamente em Planejamento quando não exige.
drop policy if exists projects_insert_open on public.projects;
create policy projects_insert_open on public.projects for insert to authenticated with check (
  (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and created_by=auth.uid()
  and (
    (requires_dimensioning=true and status='received')
    or (requires_dimensioning=false and status='planning')
  )
);

-- Datas da visita só podem ser alteradas enquanto o projeto está em Dimensionamento.
drop policy if exists date_options_operational_insert on public.date_options;
drop policy if exists date_options_operational_update on public.date_options;
drop policy if exists date_options_admin_delete on public.date_options;
create policy date_options_operational_insert on public.date_options for insert to authenticated with check (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);
create policy date_options_operational_update on public.date_options for update to authenticated using (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
) with check (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);
create policy date_options_admin_delete on public.date_options for delete to authenticated using (
  private.has_role('admin') and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);

-- Registro principal do dimensionamento: INSERT inicial na Entrada; UPDATE/DELETE apenas durante o gate.
drop policy if exists dimensionings_operational_insert on public.dimensionings;
drop policy if exists dimensionings_operational_update on public.dimensionings;
drop policy if exists dimensionings_admin_delete on public.dimensionings;
create policy dimensionings_operational_insert on public.dimensionings for insert to authenticated with check (
  (private.has_role('admin') or private.has_role('commercial') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status in ('received','awaiting_dimensioning') and p.deleted_at is null)
);
create policy dimensionings_operational_update on public.dimensionings for update to authenticated using (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
) with check (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);
create policy dimensionings_admin_delete on public.dimensionings for delete to authenticated using (
  private.has_role('admin') and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);

-- Cenários só são mutáveis durante Dimensionamento.
drop policy if exists dimensioning_options_operational_insert on public.dimensioning_options;
drop policy if exists dimensioning_options_operational_update on public.dimensioning_options;
drop policy if exists dimensioning_options_admin_delete on public.dimensioning_options;
create policy dimensioning_options_operational_insert on public.dimensioning_options for insert to authenticated with check (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.dimensionings d join public.projects p on p.id=d.project_id where d.id=dimensioning_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);
create policy dimensioning_options_operational_update on public.dimensioning_options for update to authenticated using (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.dimensionings d join public.projects p on p.id=d.project_id where d.id=dimensioning_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
) with check (
  (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.dimensionings d join public.projects p on p.id=d.project_id where d.id=dimensioning_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);
create policy dimensioning_options_admin_delete on public.dimensioning_options for delete to authenticated using (
  private.has_role('admin') and exists(select 1 from public.dimensionings d join public.projects p on p.id=d.project_id where d.id=dimensioning_id and p.status='awaiting_dimensioning' and p.deleted_at is null)
);

-- Validação de TI só é mutável durante o gate TI.
drop policy if exists ti_validations_authorized_insert on public.ti_validations;
drop policy if exists ti_validations_authorized_update on public.ti_validations;
drop policy if exists ti_validations_admin_delete on public.ti_validations;
create policy ti_validations_authorized_insert on public.ti_validations for insert to authenticated with check (
  (private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_ti' and p.deleted_at is null)
);
create policy ti_validations_authorized_update on public.ti_validations for update to authenticated using (
  (private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_ti' and p.deleted_at is null)
) with check (
  (private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager'))
  and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_ti' and p.deleted_at is null)
);
create policy ti_validations_admin_delete on public.ti_validations for delete to authenticated using (
  private.has_role('admin') and exists(select 1 from public.projects p where p.id=project_id and p.status='awaiting_ti' and p.deleted_at is null)
);
