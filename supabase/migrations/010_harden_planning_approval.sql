-- Endurece a aprovação: valida o conteúdo no servidor e impede mudanças diretas de status.
create or replace function private.assert_positive_integer(value_text text, field_label text)
returns void
language plpgsql
immutable
set search_path = pg_catalog
as $$
begin
  if coalesce(value_text,'') !~ '^[1-9][0-9]*$' then
    raise exception '% deve ser um número inteiro maior que zero.', field_label;
  end if;
end;
$$;

create or replace function private.assert_planning_content(p_content jsonb)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  store jsonb;
  item jsonb;
  day_item jsonb;
  area_item jsonb;
  role_item jsonb;
  activity_item jsonb;
  checklist_key text;
  items jsonb;
  inventory_start text;
  inventory_end text;
  pre_start text;
  pre_end text;
  total_dates integer;
  distinct_dates integer;
begin
  if p_content is null or jsonb_typeof(p_content) <> 'object' then
    raise exception 'O conteúdo do planejamento é inválido.';
  end if;

  store := p_content->'store';
  if jsonb_typeof(store) <> 'object' then raise exception 'As informações da loja são obrigatórias.'; end if;
  if btrim(coalesce(store->>'unit','')) = '' then raise exception 'Informe a unidade da loja.'; end if;
  perform private.assert_positive_integer(store->>'headcount','Efetivo geral');
  inventory_start := store->>'inventoryStart';
  inventory_end := store->>'inventoryEnd';
  if coalesce(inventory_start,'') = '' or coalesce(inventory_end,'') = '' then raise exception 'Informe o período do inventário.'; end if;
  if inventory_start > inventory_end then raise exception 'O início do inventário deve ser anterior ou igual ao fim.'; end if;

  items := coalesce(p_content->'responsibilities','[]'::jsonb);
  if jsonb_typeof(items) <> 'array' then raise exception 'A lista de responsáveis é inválida.'; end if;
  if jsonb_array_length(items)=0 then raise exception 'Cadastre os responsáveis pela operação.'; end if;
  for item in select value from jsonb_array_elements(items) loop
    if btrim(coalesce(item->>'role',''))='' or btrim(coalesce(item->>'person',''))='' then
      raise exception 'Todas as funções devem possuir um responsável.';
    end if;
  end loop;

  items := coalesce(p_content#>'{logistics,transports}','[]'::jsonb);
  if jsonb_typeof(items)<>'array' then raise exception 'A lista de transportes é inválida.'; end if;
  for item in select value from jsonb_array_elements(items) loop
    if btrim(coalesce(item->>'date',''))='' or btrim(coalesce(item->>'time',''))='' or btrim(coalesce(item->>'route',''))='' or btrim(coalesce(item->>'passengers',''))='' then raise exception 'Preencha data, horário, trajeto e passageiros de todos os transportes.'; end if;
    perform private.assert_positive_integer(item->>'quantity','Quantidade do transporte');
    if item->>'date'<inventory_start or item->>'date'>inventory_end then raise exception 'Há transporte fora do período do inventário.'; end if;
  end loop;

  items := coalesce(p_content#>'{logistics,accommodations}','[]'::jsonb);
  if jsonb_typeof(items)<>'array' then raise exception 'A lista de hospedagens é inválida.'; end if;
  for item in select value from jsonb_array_elements(items) loop
    if btrim(coalesce(item->>'guests',''))='' or btrim(coalesce(item->>'rooms',''))='' or btrim(coalesce(item->>'checkIn',''))='' or btrim(coalesce(item->>'checkOut',''))='' then raise exception 'Preencha hóspedes, quartos, entrada e saída de todas as hospedagens.'; end if;
    perform private.assert_positive_integer(item->>'count','Quantidade de hóspedes');
    if item->>'checkIn'>item->>'checkOut' then raise exception 'Há hospedagem com entrada posterior à saída.'; end if;
  end loop;

  foreach checklist_key in array array['clientEquipment','contagemEquipment'] loop
    items := coalesce(p_content #> array[checklist_key,'rows'], '[]'::jsonb);
    if jsonb_typeof(items)<>'array' then raise exception 'A lista de equipamentos é inválida.'; end if;
    for item in select value from jsonb_array_elements(items) loop
      if btrim(coalesce(item->>'equipment',''))='' or btrim(coalesce(item->>'date',''))='' or btrim(coalesce(item->>'shift',''))='' or btrim(coalesce(item->>'status',''))='' then raise exception 'Preencha equipamento, dia, turno e status de todos os equipamentos.'; end if;
      perform private.assert_positive_integer(item->>'quantity','Quantidade de equipamentos');
      if item->>'date'<inventory_start or item->>'date'>inventory_end then raise exception 'Há equipamento fora do período do inventário.'; end if;
    end loop;
  end loop;

  if coalesce(store->>'preCountEnabled','false')='true' then
    pre_start := store->>'preStart'; pre_end := store->>'preEnd';
    if coalesce(pre_start,'')='' or coalesce(pre_end,'')='' then raise exception 'Informe o período da pré-contagem.'; end if;
    if pre_start > pre_end or pre_end > inventory_start then raise exception 'O período da pré-contagem é inconsistente.'; end if;
    items := coalesce(p_content#>'{preCount,rows}','[]'::jsonb);
    if jsonb_typeof(items)<>'array' then raise exception 'A lista de pré-contagem é inválida.'; end if;
    if jsonb_array_length(items)=0 then raise exception 'Cadastre ao menos uma equipe de pré-contagem.'; end if;
    for item in select value from jsonb_array_elements(items) loop
      if btrim(coalesce(item->>'date',''))='' or btrim(coalesce(item->>'time',''))='' or btrim(coalesce(item->>'team',''))='' then raise exception 'Preencha data, horário e equipe da pré-contagem.'; end if;
      perform private.assert_positive_integer(item->>'count','Quantidade da pré-contagem');
      if item->>'date' < pre_start or item->>'date' > pre_end then raise exception 'A data da pré-contagem está fora do período.'; end if;
    end loop;
  end if;

  items := coalesce(p_content->'days','[]'::jsonb);
  if jsonb_typeof(items)<>'array' then raise exception 'A lista de dias é inválida.'; end if;
  if jsonb_array_length(items)=0 then raise exception 'Cadastre ao menos um dia de inventário.'; end if;
  select count(*),count(distinct value->>'date') into total_dates,distinct_dates from jsonb_array_elements(items);
  if total_dates<>distinct_dates then raise exception 'Existem datas duplicadas nos dias do inventário.'; end if;
  for day_item in select value from jsonb_array_elements(items) loop
    if btrim(coalesce(day_item->>'date',''))='' or day_item->>'date'<inventory_start or day_item->>'date'>inventory_end then raise exception 'Há um dia fora do período do inventário.'; end if;
    perform private.assert_positive_integer(day_item->>'headcount','Equipe prevista do dia');
    if jsonb_typeof(coalesce(day_item->'areas','[]'::jsonb))<>'array' then raise exception 'A lista de áreas do dia é inválida.'; end if;
    if jsonb_array_length(coalesce(day_item->'areas','[]'::jsonb))=0 then raise exception 'Cada dia deve possuir ao menos uma área ou turno.'; end if;
    for area_item in select value from jsonb_array_elements(coalesce(day_item->'areas','[]'::jsonb)) loop
      if btrim(coalesce(area_item->>'name',''))='' or btrim(coalesce(area_item->>'shift',''))='' or btrim(coalesce(area_item->>'startsAt',''))='' then raise exception 'Preencha nome, turno e início de todas as áreas.'; end if;
      perform private.assert_positive_integer(area_item->>'headcount','Equipe prevista da área');
      if jsonb_typeof(coalesce(area_item->'roles','[]'::jsonb))<>'array' then raise exception 'A lista de funções da área é inválida.'; end if;
      if jsonb_typeof(coalesce(area_item->'activities','[]'::jsonb))<>'array' then raise exception 'A lista de atividades da área é inválida.'; end if;
      for role_item in select value from jsonb_array_elements(coalesce(area_item->'roles','[]'::jsonb)) loop
        if btrim(coalesce(role_item->>'role',''))='' then raise exception 'Preencha todas as funções das equipes.'; end if;
        perform private.assert_positive_integer(role_item->>'count','Quantidade por função');
      end loop;
      for activity_item in select value from jsonb_array_elements(coalesce(area_item->'activities','[]'::jsonb)) loop
        if btrim(coalesce(activity_item->>'name',''))='' then raise exception 'Preencha todas as atividades das áreas.'; end if;
      end loop;
    end loop;
  end loop;

  foreach checklist_key in array array['preInventory','planning','final'] loop
    items := coalesce(p_content #> array['checklists',checklist_key], '[]'::jsonb);
    if jsonb_typeof(items)<>'array' then raise exception 'A estrutura dos checklists é inválida.'; end if;
    if jsonb_array_length(items)=0 then raise exception 'Todos os checklists devem conter itens.'; end if;
    if exists(select 1 from jsonb_array_elements(items) checklist_item where btrim(coalesce(checklist_item->>'label',''))='' or coalesce((checklist_item->>'done')::boolean,false)=false) then
      raise exception 'Todos os itens dos checklists devem estar preenchidos e concluídos.';
    end if;
  end loop;
end;
$$;

create or replace function public.approve_planning(p_project_id uuid,p_content jsonb,p_completion_percentage numeric)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'Usuário não autenticado.'; end if;
  if not (private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas administradores, supervisores ou gestores operacionais podem aprovar o planejamento.';
  end if;
  if not exists(select 1 from public.projects where id=p_project_id and deleted_at is null and status in ('planning','awaiting_dates')) then
    raise exception 'O projeto não está em uma etapa elegível para aprovação.';
  end if;
  perform private.assert_planning_content(p_content);
  perform set_config('app.secure_planning_approval',p_project_id::text,true);

  insert into public.plannings(project_id,content,completion_percentage,status,started_by,approved_by,approved_at,updated_at)
  values(p_project_id,p_content,100,'approved',auth.uid(),auth.uid(),now(),now())
  on conflict(project_id) do update set content=excluded.content,completion_percentage=100,status='approved',started_by=coalesce(public.plannings.started_by,excluded.started_by),approved_by=auth.uid(),approved_at=now(),updated_at=now(),version=coalesce(public.plannings.version,0)+1;

  update public.projects set status='confirmed',updated_by=auth.uid(),updated_at=now() where id=p_project_id and deleted_at is null;
end;
$$;

create or replace function private.guard_planning_approval_status()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  if new.status='approved' or (tg_op='UPDATE' and old.status='approved') then
    if current_setting('app.secure_planning_approval',true) is distinct from new.project_id::text then
      raise exception 'Use a operação segura de aprovação do planejamento.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_planning_approval_status on public.plannings;
create trigger guard_planning_approval_status before insert or update on public.plannings for each row execute function private.guard_planning_approval_status();

create or replace function private.guard_project_confirmation_status()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  if new.status='confirmed' then
    if current_setting('app.secure_planning_approval',true) is distinct from new.id::text then
      raise exception 'Use a operação segura de aprovação do planejamento.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_project_confirmation_status on public.projects;
create trigger guard_project_confirmation_status before insert or update on public.projects for each row execute function private.guard_project_confirmation_status();

revoke all on function public.approve_planning(uuid,jsonb,numeric) from public,anon;
grant execute on function public.approve_planning(uuid,jsonb,numeric) to authenticated;
