-- Aprovação transacional e restrita por papel.
create or replace function public.approve_planning(
  p_project_id uuid,
  p_content jsonb,
  p_completion_percentage numeric
) returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  checklist_key text;
  checklist_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not (
    private.has_role('admin') or
    private.has_role('operational_supervisor') or
    private.has_role('operational_manager')
  ) then
    raise exception 'Apenas administradores, supervisores ou gestores operacionais podem aprovar o planejamento.';
  end if;

  if p_completion_percentage <> 100 then
    raise exception 'O planejamento precisa estar 100%% concluído para aprovação.';
  end if;

  foreach checklist_key in array array['preInventory','planning','final'] loop
    checklist_items := coalesce(p_content #> array['checklists', checklist_key], '[]'::jsonb);
    if jsonb_typeof(checklist_items) <> 'array' or jsonb_array_length(checklist_items) = 0 then
      raise exception 'Todos os checklists devem conter itens.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(checklist_items) item
      where btrim(coalesce(item->>'label','')) = ''
         or coalesce((item->>'done')::boolean, false) = false
    ) then
      raise exception 'Todos os itens dos checklists devem estar preenchidos e concluídos.';
    end if;
  end loop;

  insert into public.plannings(
    project_id, content, completion_percentage, status,
    started_by, approved_by, approved_at, updated_at
  ) values (
    p_project_id, p_content, p_completion_percentage, 'approved',
    auth.uid(), auth.uid(), now(), now()
  )
  on conflict (project_id) do update set
    content = excluded.content,
    completion_percentage = excluded.completion_percentage,
    status = 'approved',
    started_by = coalesce(public.plannings.started_by, excluded.started_by),
    approved_by = auth.uid(),
    approved_at = now(),
    updated_at = now(),
    version = coalesce(public.plannings.version, 0) + 1;

  update public.projects
  set status = 'confirmed', updated_by = auth.uid(), updated_at = now()
  where id = p_project_id and deleted_at is null;

  if not found then
    raise exception 'Projeto não encontrado ou indisponível.';
  end if;
end;
$$;

revoke all on function public.approve_planning(uuid,jsonb,numeric) from public, anon;
grant execute on function public.approve_planning(uuid,jsonb,numeric) to authenticated;
