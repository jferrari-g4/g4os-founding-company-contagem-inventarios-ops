-- Corrige coerção do enum dimensioning_status no salvamento de rascunho.

create or replace function public.save_dimensioning_draft(
  p_project_id uuid,
  p_options jsonb,
  p_selected_option_id uuid default null,
  p_visit_starts timestamptz[] default array[]::timestamptz[],
  p_notes text default null
)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare
  v_dimensioning_id uuid;
  v_option jsonb;
  v_option_id uuid;
  v_visit_count integer:=coalesce(array_length(p_visit_starts,1),0);
  v_index integer;
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode editar o dimensionamento.';
  end if;
  if jsonb_typeof(coalesce(p_options,'[]'::jsonb))<>'array' then raise exception 'As opções de dimensionamento devem ser uma lista.'; end if;
  if v_visit_count>2 then raise exception 'Informe no máximo duas opções de visita.'; end if;

  perform 1 from public.projects where id=p_project_id and status='awaiting_dimensioning' and deleted_at is null for update;
  if not found then raise exception 'O projeto não está aguardando dimensionamento.'; end if;

  insert into public.dimensionings(project_id,status,opened_at,notes)
  values(p_project_id,'in_progress',now(),nullif(trim(p_notes),''))
  on conflict(project_id) do update set status=case when public.dimensionings.status='open' then 'in_progress' else public.dimensionings.status end,notes=coalesce(nullif(trim(p_notes),''),public.dimensionings.notes)
  returning id into v_dimensioning_id;

  for v_option in select value from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) loop
    v_option_id=(v_option->>'id')::uuid;
    if nullif(trim(v_option->>'title'),'') is null then raise exception 'Toda opção de dimensionamento precisa de um título.'; end if;
    if exists(select 1 from public.dimensioning_options where id=v_option_id and dimensioning_id<>v_dimensioning_id) then
      raise exception 'Uma opção enviada não pertence a este dimensionamento.';
    end if;
    insert into public.dimensioning_options(id,dimensioning_id,title,days,team_size,details,approved,approved_by,approved_at)
    values(
      v_option_id,v_dimensioning_id,trim(v_option->>'title'),nullif(v_option->>'days','')::integer,
      nullif(v_option->>'team_size','')::integer,
      jsonb_build_object('notes',coalesce(v_option->>'notes','')),
      v_option_id=p_selected_option_id,
      case when v_option_id=p_selected_option_id then auth.uid() else null end,
      case when v_option_id=p_selected_option_id then now() else null end
    )
    on conflict(id) do update set
      title=excluded.title,days=excluded.days,team_size=excluded.team_size,details=excluded.details,
      approved=excluded.approved,approved_by=excluded.approved_by,approved_at=excluded.approved_at;
  end loop;

  delete from public.dimensioning_options option_row
   where option_row.dimensioning_id=v_dimensioning_id
     and not exists(select 1 from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) item where (item->>'id')::uuid=option_row.id);

  if p_selected_option_id is not null and not exists(
    select 1 from public.dimensioning_options where id=p_selected_option_id and dimensioning_id=v_dimensioning_id
  ) then raise exception 'A opção de dimensionamento selecionada não pertence ao projeto.'; end if;

  if v_visit_count=0 then
    delete from public.date_options where project_id=p_project_id;
  else
    for v_index in 1..v_visit_count loop
      insert into public.date_options(project_id,option_number,starts_at,proposed_by,status,sent_at)
      values(p_project_id,v_index,p_visit_starts[v_index],auth.uid(),'proposed',now())
      on conflict(project_id,option_number) do update set starts_at=excluded.starts_at,proposed_by=auth.uid(),status='proposed',sent_at=now(),selected_at=null,selected_by=null;
    end loop;
    delete from public.date_options where project_id=p_project_id and option_number>v_visit_count;
  end if;

  update public.dimensionings set
    status=case when p_selected_option_id is null then 'in_progress'::public.dimensioning_status else 'awaiting_approval'::public.dimensioning_status end,
    notes=coalesce(nullif(trim(p_notes),''),notes)
  where id=v_dimensioning_id;

  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id)
  values('dimensionings',p_project_id,'draft_saved',jsonb_build_object('selected_option_id',p_selected_option_id,'visit_option_count',v_visit_count),auth.uid());
end;
$$;

