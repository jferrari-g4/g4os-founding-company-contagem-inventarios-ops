-- Administração sem código, validação server-side e fundação de paridade MCP.

create or replace function public.is_authenticated() returns boolean language sql stable security definer set search_path=public,pg_catalog as $$
  select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and active)
$$;
create or replace function private.has_role(required_role public.app_role) returns boolean language sql stable security definer set search_path=public,pg_catalog as $$
  select exists(select 1 from public.user_roles ur join public.profiles p on p.id=ur.user_id where ur.user_id=auth.uid() and ur.role=required_role and p.active)
$$;
create or replace function private.g4os_assume_actor(p_actor_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if p_actor_id is null or not exists(select 1 from public.user_roles ur join public.profiles p on p.id=ur.user_id where ur.user_id=p_actor_id and p.active) then raise exception 'Ator G4 OS inválido, inativo ou sem perfil.';end if;
  perform set_config('request.jwt.claim.sub',p_actor_id::text,true);
end $$;
revoke all on function private.g4os_assume_actor(uuid) from public,anon,authenticated;
grant execute on function private.g4os_assume_actor(uuid) to service_role;

alter table public.custom_fields add column if not exists options jsonb not null default '[]'::jsonb;
alter table public.custom_fields add column if not exists required_from timestamptz;
alter table public.custom_fields add column if not exists stage text not null default 'request';
alter table public.custom_fields add column if not exists placeholder text;
alter table public.custom_fields add column if not exists help_text text;

do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.custom_fields'::regclass and conname='custom_fields_type_check') then
    alter table public.custom_fields add constraint custom_fields_type_check check(field_type in ('text','textarea','number','date','email','phone','select','checkbox'));
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.custom_fields'::regclass and conname='custom_fields_stage_check') then
    alter table public.custom_fields add constraint custom_fields_stage_check check(stage in ('request','dimensioning','ti','planning','calendar'));
  end if;
end $$;

create table if not exists public.inventory_type_catalog(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workflow_stage_catalog(
  id uuid primary key default gen_random_uuid(),
  stage_key text not null unique,
  label text not null,
  description text,
  mapped_status public.project_status,
  system_stage boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 0,
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.workflow_stage_catalog(stage_key,label,mapped_status,system_stage,sort_order,color) values
 ('received','Entrada','received',true,10,'#5E97FF'),
 ('awaiting_dimensioning','Dimensionamento','awaiting_dimensioning',true,20,'#B58E58'),
 ('awaiting_ti','TI / Datas','awaiting_ti',true,30,'#7C6BE8'),
 ('planning','Planejamento','planning',true,40,'#EC2226'),
 ('confirmed','Concluído','confirmed',true,50,'#2E9D62'),
 ('cancelled','Cancelado','cancelled',true,90,'#6B7280')
on conflict(stage_key) do update set label=excluded.label,mapped_status=excluded.mapped_status,system_stage=true,sort_order=excluded.sort_order,color=excluded.color,updated_at=now();

alter table public.planning_block_definitions drop constraint if exists planning_block_definitions_sort_order_key;
create index if not exists idx_planning_block_definitions_sort_order on public.planning_block_definitions(sort_order);
insert into public.planning_block_definitions(block_key,label,description,sort_order,required_for_completion,active) values
 ('store','Informações da loja','Períodos e efetivo geral',10,true,true),
 ('responsibilities','Responsáveis pela operação','Funções e responsáveis',20,true,true),
 ('logistics','Logística','Transporte, hospedagem e orientações',30,false,true),
 ('client_equipment','Equipamentos do cliente','Recursos fornecidos pelo cliente',40,false,true),
 ('contagem_equipment','Equipamentos Contagem','Recursos fornecidos pela Contagem',50,false,true),
 ('pre_count','Pré-contagem','Datas, horários e equipe',60,false,true),
 ('inventory_days','Dias, turnos e áreas','Estrutura diária do inventário',70,true,true),
 ('checklists','Checklists','Gates de conferência',80,true,true)
on conflict(block_key) do update set label=excluded.label,description=excluded.description,required_for_completion=excluded.required_for_completion,active=excluded.active,updated_at=now();

alter table public.projects add column if not exists workflow_stage_key text references public.workflow_stage_catalog(stage_key);

alter table public.inventory_type_catalog enable row level security;
alter table public.workflow_stage_catalog enable row level security;
drop policy if exists inventory_type_catalog_read on public.inventory_type_catalog;
create policy inventory_type_catalog_read on public.inventory_type_catalog for select to authenticated using(public.is_authenticated());
drop policy if exists inventory_type_catalog_admin_manage on public.inventory_type_catalog;
create policy inventory_type_catalog_admin_manage on public.inventory_type_catalog for all to authenticated using(private.is_admin()) with check(private.is_admin());
drop policy if exists workflow_stage_catalog_read on public.workflow_stage_catalog;
create policy workflow_stage_catalog_read on public.workflow_stage_catalog for select to authenticated using(public.is_authenticated());
drop policy if exists workflow_stage_catalog_admin_manage on public.workflow_stage_catalog;
create policy workflow_stage_catalog_admin_manage on public.workflow_stage_catalog for all to authenticated using(private.is_admin()) with check(private.is_admin());
grant select on public.inventory_type_catalog,public.workflow_stage_catalog to authenticated;
grant insert,update,delete on public.inventory_type_catalog,public.workflow_stage_catalog to authenticated;

-- Checklist final passa a ser um tipo administrável válido.
alter table public.checklist_templates drop constraint if exists checklist_templates_checklist_type_check;
alter table public.checklist_templates add constraint checklist_templates_checklist_type_check check(checklist_type in ('pre_inventory_visit','planning','final'));
alter table public.planning_checklists drop constraint if exists planning_checklists_checklist_type_check;
alter table public.planning_checklists add constraint planning_checklists_checklist_type_check check(checklist_type in ('pre_inventory_visit','planning','final'));
alter table public.planning_checklist_items drop constraint if exists planning_checklist_items_template_item_id_fkey;
alter table public.planning_checklist_items add constraint planning_checklist_items_template_item_id_fkey foreign key(template_item_id) references public.checklist_template_items(id) on delete set null;

-- Policies antigas permitiam escrita ampla. O modelo normalizado ainda não é o writer canônico;
-- por segurança, fica sem policy de escrita até wrappers transacionais específicos serem adotados.
do $$
declare t text;
begin
  foreach t in array array['planning_responsibilities','planning_transports','planning_accommodations','planning_pre_counts','planning_days','planning_day_areas','planning_area_team_roles','planning_area_activities','planning_equipment_requirements','planning_checklists','planning_checklist_items','attachments'] loop
    execute format('drop policy if exists authenticated_write_%I on public.%I',t,t);
    execute format('drop policy if exists %I_authorized_manage on public.%I',t,t);
  end loop;
end $$;

create or replace function private.field_value_present(p_value jsonb)
returns boolean language sql immutable set search_path=pg_catalog as $$
  select p_value is not null and jsonb_typeof(p_value)<>'null' and not (jsonb_typeof(p_value)='string' and btrim(p_value#>>'{}')='');
$$;

create or replace function private.assert_request_custom_fields(
  p_field_values jsonb,p_requires_dimensioning boolean,p_inventory_type text,p_layout_system text,
  p_ti_contact_name text,p_ti_contact_email text,p_ti_contact_phone text
) returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare f public.custom_fields%rowtype;v_value jsonb;v_item jsonb;
begin
  if jsonb_typeof(coalesce(p_field_values,'[]'::jsonb))<>'array' then raise exception 'Valores de campos inválidos.'; end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_field_values,'[]'::jsonb)) loop
    if nullif(v_item->>'field_id','') is null or not exists(select 1 from public.custom_fields where id=(v_item->>'field_id')::uuid and entity='project' and active) then
      raise exception 'Campo configurável inválido ou inativo.';
    end if;
  end loop;
  for f in select * from public.custom_fields where entity='project' and active and required and stage='request' and (not show_when_dimensioning or p_requires_dimensioning) loop
    if f.system_field then
      v_value=to_jsonb(case f.field_key when 'inventory_type' then p_inventory_type when 'layout_system' then p_layout_system when 'ti_contact_name' then p_ti_contact_name when 'ti_contact_email' then p_ti_contact_email when 'ti_contact_phone' then p_ti_contact_phone else null end);
    else
      select item->'value' into v_value from jsonb_array_elements(coalesce(p_field_values,'[]'::jsonb)) item where item->>'field_id'=f.id::text limit 1;
    end if;
    if not private.field_value_present(v_value) then raise exception 'Campo obrigatório não preenchido: %',f.label; end if;
  end loop;
end $$;
revoke all on function private.assert_request_custom_fields(jsonb,boolean,text,text,text,text,text) from public,anon,authenticated;

-- Validação diferida cobre frontend, MCP e qualquer futuro criador transacional.
create or replace function private.assert_existing_project_required_fields(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare f public.custom_fields%rowtype;v_value jsonb;v_project public.projects%rowtype;
begin
  select * into v_project from public.projects where id=p_project_id;if not found or coalesce(v_project.notion_origin,false) then return;end if;
  for f in select * from public.custom_fields where entity='project' and active and required and stage='request' and (required_from is null or v_project.created_at>=required_from) and (not show_when_dimensioning or v_project.requires_dimensioning) loop
    if f.system_field then
      v_value=to_jsonb(case f.field_key when 'inventory_type' then v_project.inventory_type when 'layout_system' then v_project.layout_system when 'ti_contact_name' then v_project.ti_contact_name when 'ti_contact_email' then v_project.ti_contact_email when 'ti_contact_phone' then v_project.ti_contact_phone else null end);
    else
      select value into v_value from public.project_field_values where project_id=p_project_id and field_id=f.id;
    end if;
    if not private.field_value_present(v_value) then raise exception 'Campo obrigatório não preenchido: %',f.label;end if;
  end loop;
end $$;
create or replace function private.validate_project_required_fields_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  perform private.assert_existing_project_required_fields(new.id);return new;
end $$;
drop trigger if exists validate_project_required_fields on public.projects;
create constraint trigger validate_project_required_fields after insert or update of requires_dimensioning,inventory_type,layout_system,ti_contact_name,ti_contact_email,ti_contact_phone on public.projects deferrable initially deferred for each row execute function private.validate_project_required_fields_trigger();
create or replace function private.validate_project_field_value_trigger() returns trigger language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if tg_op='DELETE' then perform private.assert_existing_project_required_fields(old.project_id);return old;end if;
  if tg_op='UPDATE' and old.project_id is distinct from new.project_id then perform private.assert_existing_project_required_fields(old.project_id);end if;
  perform private.assert_existing_project_required_fields(new.project_id);return new;
end $$;
drop trigger if exists validate_project_field_values on public.project_field_values;
create constraint trigger validate_project_field_values after insert or update or delete on public.project_field_values deferrable initially deferred for each row execute function private.validate_project_field_value_trigger();

create or replace function private.stamp_custom_field_required_from() returns trigger language plpgsql set search_path=public,pg_catalog as $$
begin
  if new.required and new.active and (tg_op='INSERT' or not coalesce(old.required,false) or not coalesce(old.active,false)) and new.required_from is null then new.required_from=now();end if;
  return new;
end $$;
drop trigger if exists stamp_custom_field_required_from on public.custom_fields;
create trigger stamp_custom_field_required_from before insert or update of required,active on public.custom_fields for each row execute function private.stamp_custom_field_required_from();

create or replace function private.guard_system_custom_field_update() returns trigger language plpgsql set search_path=public,pg_catalog as $$
begin
  if old.system_field and (new.field_key is distinct from old.field_key or new.field_type is distinct from old.field_type or new.entity is distinct from old.entity or not new.system_field) then raise exception 'A estrutura de campos-base é protegida.';end if;
  return new;
end $$;
drop trigger if exists guard_system_custom_field_update on public.custom_fields;
create trigger guard_system_custom_field_update before update on public.custom_fields for each row execute function private.guard_system_custom_field_update();

create or replace function private.guard_profile_active_change() returns trigger language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if new.active is distinct from old.active and not private.is_admin() then raise exception 'Somente administradores podem alterar o status de acesso.';end if;return new;
end $$;
drop trigger if exists guard_profile_active_change on public.profiles;
create trigger guard_profile_active_change before update of active on public.profiles for each row execute function private.guard_profile_active_change();

-- Protege o último administrador ativo contra autoexclusão e concorrência.
create or replace function private.guard_last_admin_role() returns trigger language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('contagem_guard_last_admin',0));
  if old.role='admin' and (tg_op='DELETE' or new.role is distinct from old.role or new.user_id is distinct from old.user_id) and not exists(select 1 from public.user_roles ur join public.profiles p on p.id=ur.user_id where ur.role='admin' and p.active and ur.user_id<>old.user_id) then raise exception 'Não é possível remover o último administrador ativo.';end if;
  if tg_op='DELETE' then return old;end if;return new;
end $$;
create or replace function private.guard_last_admin_profile() returns trigger language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('contagem_guard_last_admin',0));
  if old.active and not new.active and exists(select 1 from public.user_roles where user_id=old.id and role='admin') and not exists(select 1 from public.user_roles ur join public.profiles p on p.id=ur.user_id where ur.role='admin' and p.active and ur.user_id<>old.id) then raise exception 'Não é possível desativar o último administrador ativo.';end if;
  return new;
end $$;
drop trigger if exists guard_last_admin_role on public.user_roles;
create trigger guard_last_admin_role before delete or update of user_id,role on public.user_roles for each row execute function private.guard_last_admin_role();
drop trigger if exists guard_last_admin_profile on public.profiles;
create trigger guard_last_admin_profile before update of active on public.profiles for each row execute function private.guard_last_admin_profile();

-- CRUD genérico e allowlisted para Administração via MCP.
create or replace function public.g4os_upsert_admin_catalog(p_actor_id uuid,p_catalog text,p_item jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_id uuid;v_result jsonb;v_key text;
begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem gerenciar catálogos.';end if;
  v_id=nullif(p_item->>'id','')::uuid;
  case p_catalog
    when 'roles' then
      if btrim(coalesce(p_item->>'name',''))='' then raise exception 'Nome obrigatório.';end if;
      if v_id is null then insert into public.planning_role_catalog(name,category,active,sort_order) values(btrim(p_item->>'name'),nullif(btrim(p_item->>'category'),''),coalesce((p_item->>'active')::boolean,true),coalesce((p_item->>'sort_order')::integer,0)) returning id into v_id;
      else update public.planning_role_catalog set name=btrim(p_item->>'name'),category=nullif(btrim(p_item->>'category'),''),active=coalesce((p_item->>'active')::boolean,active),sort_order=coalesce((p_item->>'sort_order')::integer,sort_order) where id=v_id returning id into v_id;end if;
      select to_jsonb(x) into v_result from public.planning_role_catalog x where id=v_id;
    when 'activities' then
      if btrim(coalesce(p_item->>'name',''))='' then raise exception 'Nome obrigatório.';end if;
      if v_id is null then insert into public.planning_activity_catalog(name,area_type,active,sort_order) values(btrim(p_item->>'name'),nullif(btrim(p_item->>'area_type'),''),coalesce((p_item->>'active')::boolean,true),coalesce((p_item->>'sort_order')::integer,0)) returning id into v_id;
      else update public.planning_activity_catalog set name=btrim(p_item->>'name'),area_type=nullif(btrim(p_item->>'area_type'),''),active=coalesce((p_item->>'active')::boolean,active),sort_order=coalesce((p_item->>'sort_order')::integer,sort_order) where id=v_id returning id into v_id;end if;
      select to_jsonb(x) into v_result from public.planning_activity_catalog x where id=v_id;
    when 'equipment' then
      if btrim(coalesce(p_item->>'name',''))='' or coalesce(p_item->>'owner_type','') not in ('client','contagem') then raise exception 'Nome e proprietário válidos são obrigatórios.';end if;
      if v_id is null then insert into public.equipment_catalog(owner_type,name,active) values(p_item->>'owner_type',btrim(p_item->>'name'),coalesce((p_item->>'active')::boolean,true)) returning id into v_id;
      else update public.equipment_catalog set owner_type=p_item->>'owner_type',name=btrim(p_item->>'name'),active=coalesce((p_item->>'active')::boolean,active) where id=v_id and not notion_origin returning id into v_id;end if;
      select to_jsonb(x) into v_result from public.equipment_catalog x where id=v_id;
    when 'blocks' then
      v_key=coalesce(nullif(btrim(p_item->>'block_key'),''),'custom_'||replace(gen_random_uuid()::text,'-',''));
      if btrim(coalesce(p_item->>'label',''))='' then raise exception 'Rótulo obrigatório.';end if;
      if v_id is null then insert into public.planning_block_definitions(block_key,label,description,sort_order,required_for_completion,active) values(v_key,btrim(p_item->>'label'),nullif(btrim(p_item->>'description'),''),coalesce((p_item->>'sort_order')::integer,0),coalesce((p_item->>'required_for_completion')::boolean,false),coalesce((p_item->>'active')::boolean,true)) returning id into v_id;
      else update public.planning_block_definitions set label=btrim(p_item->>'label'),description=nullif(btrim(p_item->>'description'),''),sort_order=coalesce((p_item->>'sort_order')::integer,sort_order),required_for_completion=coalesce((p_item->>'required_for_completion')::boolean,required_for_completion),active=coalesce((p_item->>'active')::boolean,active),updated_at=now() where id=v_id returning id into v_id;end if;
      select to_jsonb(x) into v_result from public.planning_block_definitions x where id=v_id;
    when 'inventory_types' then
      if btrim(coalesce(p_item->>'name',''))='' then raise exception 'Nome obrigatório.';end if;
      if v_id is null then insert into public.inventory_type_catalog(name,description,active,sort_order) values(btrim(p_item->>'name'),nullif(btrim(p_item->>'description'),''),coalesce((p_item->>'active')::boolean,true),coalesce((p_item->>'sort_order')::integer,0)) returning id into v_id;
      else update public.inventory_type_catalog set name=btrim(p_item->>'name'),description=nullif(btrim(p_item->>'description'),''),active=coalesce((p_item->>'active')::boolean,active),sort_order=coalesce((p_item->>'sort_order')::integer,sort_order),updated_at=now() where id=v_id returning id into v_id;end if;
      select to_jsonb(x) into v_result from public.inventory_type_catalog x where id=v_id;
    when 'workflow_stages' then
      v_key=coalesce(nullif(btrim(p_item->>'stage_key'),''),'custom_'||replace(gen_random_uuid()::text,'-',''));
      if btrim(coalesce(p_item->>'label',''))='' then raise exception 'Rótulo obrigatório.';end if;
      if v_id is null then insert into public.workflow_stage_catalog(stage_key,label,description,system_stage,active,sort_order,color) values(v_key,btrim(p_item->>'label'),nullif(btrim(p_item->>'description'),''),false,coalesce((p_item->>'active')::boolean,true),coalesce((p_item->>'sort_order')::integer,0),nullif(btrim(p_item->>'color'),'')) returning id into v_id;
      else update public.workflow_stage_catalog set label=btrim(p_item->>'label'),description=nullif(btrim(p_item->>'description'),''),active=coalesce((p_item->>'active')::boolean,active),sort_order=coalesce((p_item->>'sort_order')::integer,sort_order),color=nullif(btrim(p_item->>'color'),'') where id=v_id returning id into v_id;end if;
      select to_jsonb(x) into v_result from public.workflow_stage_catalog x where id=v_id;
    else raise exception 'Catálogo não permitido.';
  end case;
  if v_id is null then raise exception 'Item não encontrado ou protegido.';end if;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('admin_catalog',v_id,'upsert',jsonb_build_object('catalog',p_catalog,'item',v_result),p_actor_id);
  return v_result;
end $$;

create or replace function public.g4os_upsert_checklist_template(p_actor_id uuid,p_template_id uuid,p_name text,p_checklist_type text,p_inventory_type text,p_active boolean,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_id uuid;v_item jsonb;v_result jsonb;
begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem gerenciar checklists.';end if;
  if btrim(coalesce(p_name,''))='' or p_checklist_type not in ('pre_inventory_visit','planning','final') then raise exception 'Nome e tipo de checklist válidos são obrigatórios.';end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception 'Itens inválidos.';end if;
  if p_template_id is null then insert into public.checklist_templates(name,checklist_type,inventory_type,active) values(btrim(p_name),p_checklist_type,nullif(btrim(p_inventory_type),''),coalesce(p_active,true)) returning id into v_id;
  else update public.checklist_templates set name=btrim(p_name),checklist_type=p_checklist_type,inventory_type=nullif(btrim(p_inventory_type),''),active=coalesce(p_active,active) where id=p_template_id returning id into v_id;end if;
  if v_id is null then raise exception 'Checklist não encontrado.';end if;
  delete from public.checklist_template_items where template_id=v_id;
  for v_item in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    if btrim(coalesce(v_item->>'label',''))<>'' then insert into public.checklist_template_items(template_id,label,required,sort_order) values(v_id,btrim(v_item->>'label'),coalesce((v_item->>'required')::boolean,true),coalesce((v_item->>'sort_order')::integer,0));end if;
  end loop;
  select to_jsonb(t) || jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.sort_order),'[]'::jsonb) from public.checklist_template_items i where i.template_id=v_id)) into v_result from public.checklist_templates t where t.id=v_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('checklist_templates',v_id,'upsert',v_result,p_actor_id);
  return v_result;
end $$;

create or replace function public.g4os_set_user_access(p_actor_id uuid,p_user_id uuid,p_full_name text,p_active boolean,p_roles text[])
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_role text;v_result jsonb;
begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem gerenciar usuários.';end if;
  if p_user_id=p_actor_id and (not coalesce(p_active,true) or not ('admin'=any(coalesce(p_roles,array[]::text[])))) then raise exception 'Você não pode remover seu próprio acesso administrativo.';end if;
  update public.profiles set full_name=coalesce(nullif(btrim(p_full_name),''),full_name),active=coalesce(p_active,active),updated_at=now() where id=p_user_id;
  if not found then raise exception 'Usuário não encontrado.';end if;
  delete from public.user_roles where user_id=p_user_id and role::text<>all(coalesce(p_roles,array[]::text[]));
  foreach v_role in array coalesce(p_roles,array[]::text[]) loop insert into public.user_roles(user_id,role) values(p_user_id,v_role::public.app_role) on conflict do nothing;end loop;
  select to_jsonb(p) || jsonb_build_object('roles',(select coalesce(jsonb_agg(role),'[]'::jsonb) from public.user_roles where user_id=p_user_id)) into v_result from public.profiles p where id=p_user_id;
  if p_active=false then update public.contagem_g4os_connections set active=false,revoked_at=coalesce(revoked_at,now()) where owner_user_id=p_user_id and active;end if;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('profiles',p_user_id,'access_updated',v_result,p_actor_id);
  return v_result;
end $$;

create or replace function public.g4os_manage_project_lifecycle(p_actor_id uuid,p_project_id uuid,p_action text,p_reason text default null,p_stage_key text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_project public.projects%rowtype;
begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem alterar o lifecycle.';end if;
  select * into v_project from public.projects where id=p_project_id for update;if not found then raise exception 'Operação não encontrada.';end if;
  if p_action<>'restore' and v_project.deleted_at is not null then raise exception 'Operação arquivada só pode ser restaurada.';end if;
  case p_action
    when 'cancel' then if v_project.status='confirmed' then raise exception 'Planejamento concluído é imutável; crie uma revisão.';end if;update public.projects set status='cancelled',operational_notes=concat_ws(E'\n',operational_notes,'Cancelamento: '||coalesce(p_reason,'Sem motivo')),updated_by=p_actor_id,updated_at=now() where id=p_project_id;
    when 'archive' then update public.projects set deleted_at=now(),operational_notes=concat_ws(E'\n',operational_notes,'Arquivamento: '||coalesce(p_reason,'Sem motivo')),updated_by=p_actor_id,updated_at=now() where id=p_project_id;
    when 'restore' then update public.projects set deleted_at=null,updated_by=p_actor_id,updated_at=now() where id=p_project_id;
    when 'set_custom_stage' then if not exists(select 1 from public.workflow_stage_catalog where stage_key=p_stage_key and active and not system_stage) then raise exception 'Etapa customizada inválida.';end if;update public.projects set workflow_stage_key=p_stage_key,updated_by=p_actor_id,updated_at=now() where id=p_project_id;
    when 'clear_custom_stage' then update public.projects set workflow_stage_key=null,updated_by=p_actor_id,updated_at=now() where id=p_project_id;
    else raise exception 'Ação de lifecycle inválida.';
  end case;
  select * into v_project from public.projects where id=p_project_id;
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('projects',p_project_id,'lifecycle_'||p_action,jsonb_build_object('reason',p_reason,'stage_key',p_stage_key),p_actor_id);
  return to_jsonb(v_project);
end $$;

create or replace function public.g4os_upsert_custom_field_v2(p_actor_id uuid,p_field_id uuid,p_field_key text,p_label text,p_field_type text,p_required boolean,p_active boolean,p_stage text,p_show_when_dimensioning boolean,p_sort_order integer,p_options jsonb,p_placeholder text,p_help_text text)
returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$ declare v_id uuid;begin
  perform private.g4os_assume_actor(p_actor_id);if not private.is_admin() then raise exception 'Somente administradores podem gerenciar campos.';end if;
  if btrim(coalesce(p_label,''))='' or p_field_type not in ('text','textarea','number','date','email','phone','select','checkbox') or p_stage not in ('request','dimensioning','ti','planning','calendar') then raise exception 'Definição de campo inválida.';end if;
  if coalesce(p_required,false) and p_stage<>'request' then raise exception 'Campos obrigatórios são suportados apenas na etapa Solicitação.';end if;
  if jsonb_typeof(coalesce(p_options,'[]'::jsonb))<>'array' then raise exception 'Opções inválidas.';end if;
  if p_field_id is null then
    insert into public.custom_fields(entity,field_key,label,field_type,required,active,sort_order,system_field,show_when_dimensioning,options,stage,placeholder,help_text)
    values('project',coalesce(nullif(btrim(p_field_key),''),'custom_'||replace(gen_random_uuid()::text,'-','')),btrim(p_label),p_field_type,coalesce(p_required,false),coalesce(p_active,true),coalesce(p_sort_order,0),false,coalesce(p_show_when_dimensioning,false),coalesce(p_options,'[]'::jsonb),p_stage,nullif(btrim(p_placeholder),''),nullif(btrim(p_help_text),'')) returning id into v_id;
  else
    update public.custom_fields set label=btrim(p_label),field_type=case when system_field then field_type else p_field_type end,required=coalesce(p_required,required),active=coalesce(p_active,active),sort_order=coalesce(p_sort_order,sort_order),show_when_dimensioning=coalesce(p_show_when_dimensioning,show_when_dimensioning),options=coalesce(p_options,options),stage=p_stage,placeholder=nullif(btrim(p_placeholder),''),help_text=nullif(btrim(p_help_text),'') where id=p_field_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Campo não encontrado.';end if;return v_id;
end $$;

create or replace function public.g4os_update_project_core(p_actor_id uuid,p_project_id uuid,p_expected_updated_at timestamptz,p_project jsonb,p_client jsonb,p_contact jsonb,p_field_values jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_project public.projects%rowtype;v_client_id uuid;v_item jsonb;
begin
  perform private.g4os_assume_actor(p_actor_id);
  if not (private.has_role('admin') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then raise exception 'Seu perfil não pode editar o cadastro da operação.';end if;
  select * into v_project from public.projects where id=p_project_id and deleted_at is null for update;if not found then raise exception 'Operação não encontrada.';end if;
  if v_project.status in ('confirmed','cancelled') then raise exception 'Operação concluída ou cancelada é imutável.';end if;
  if p_expected_updated_at is not null and v_project.updated_at is distinct from p_expected_updated_at then raise exception 'Conflito de edição: a operação foi alterada por outro usuário.';end if;
  v_client_id=v_project.client_id;
  if v_client_id is not null and p_client is not null then update public.clients set legal_name=coalesce(nullif(btrim(p_client->>'legal_name'),''),legal_name),trade_name=case when p_client?'trade_name' then nullif(btrim(p_client->>'trade_name'),'') else trade_name end,address=case when p_client?'address' then nullif(btrim(p_client->>'address'),'') else address end where id=v_client_id;end if;
  if v_client_id is not null and p_contact is not null then
    update public.client_contacts set name=coalesce(nullif(btrim(p_contact->>'name'),''),name),email=case when p_contact?'email' then nullif(btrim(p_contact->>'email'),'') else email end,phone=case when p_contact?'phone' then nullif(btrim(p_contact->>'phone'),'') else phone end where client_id=v_client_id and is_primary;
  end if;
  update public.projects set inventory_type=case when p_project?'inventory_type' then nullif(btrim(p_project->>'inventory_type'),'') else inventory_type end,layout_system=case when p_project?'layout_system' then nullif(btrim(p_project->>'layout_system'),'') else layout_system end,ti_contact_name=case when p_project?'ti_contact_name' then nullif(btrim(p_project->>'ti_contact_name'),'') else ti_contact_name end,ti_contact_email=case when p_project?'ti_contact_email' then nullif(btrim(p_project->>'ti_contact_email'),'') else ti_contact_email end,ti_contact_phone=case when p_project?'ti_contact_phone' then nullif(btrim(p_project->>'ti_contact_phone'),'') else ti_contact_phone end,operational_notes=case when p_project?'operational_notes' then nullif(btrim(p_project->>'operational_notes'),'') else operational_notes end,updated_by=p_actor_id,updated_at=now() where id=p_project_id returning * into v_project;
  if p_field_values is not null then
    if jsonb_typeof(p_field_values)<>'array' then raise exception 'Valores customizados inválidos.';end if;
    for v_item in select value from jsonb_array_elements(p_field_values) loop
      if not exists(select 1 from public.custom_fields where id=(v_item->>'field_id')::uuid and entity='project' and active) then raise exception 'Campo configurável inválido.';end if;
      insert into public.project_field_values(project_id,field_id,value) values(p_project_id,(v_item->>'field_id')::uuid,v_item->'value') on conflict(project_id,field_id) do update set value=excluded.value;
    end loop;
  end if;
  perform private.assert_existing_project_required_fields(p_project_id);
  insert into public.audit_logs(entity,entity_id,action,after_data,actor_id) values('projects',p_project_id,'core_updated',jsonb_build_object('project',p_project,'client',p_client,'contact',p_contact),p_actor_id);
  return to_jsonb(v_project);
end $$;

drop function if exists public.g4os_save_dimensioning_draft(uuid,uuid,jsonb,uuid,timestamptz[],text);
create function public.g4os_save_dimensioning_draft(p_actor_id uuid,p_project_id uuid,p_options jsonb,p_selected_option_id uuid,p_visit_starts timestamptz[],p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.g4os_assume_actor(p_actor_id);perform public.save_dimensioning_draft(p_project_id,p_options,p_selected_option_id,p_visit_starts,p_notes);end $$;

create or replace function public.g4os_list_projects(p_actor_id uuid,p_status public.project_status,p_search text,p_limit integer,p_offset integer)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_total integer;v_items jsonb;v_term text:='%'||coalesce(btrim(p_search),'')||'%';
begin
  perform private.g4os_assume_actor(p_actor_id);
  select count(*) into v_total from public.projects p left join public.clients c on c.id=p.client_id where p.deleted_at is null and (p_status is null or p.status=p_status) and (coalesce(btrim(p_search),'')='' or p.reference ilike v_term or p.inventory_type ilike v_term or c.legal_name ilike v_term or c.trade_name ilike v_term or c.cnpj ilike v_term);
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc),'[]'::jsonb) into v_items from (select p.id,p.reference,p.status,p.inventory_type,p.requires_dimensioning,p.created_at,c.legal_name as company,c.trade_name,c.cnpj,(select pl.content->'store'->>'inventoryStart' from public.plannings pl where pl.project_id=p.id) as inventory_start from public.projects p left join public.clients c on c.id=p.client_id where p.deleted_at is null and (p_status is null or p.status=p_status) and (coalesce(btrim(p_search),'')='' or p.reference ilike v_term or p.inventory_type ilike v_term or c.legal_name ilike v_term or c.trade_name ilike v_term or c.cnpj ilike v_term) order by p.created_at desc,p.id desc limit greatest(1,least(coalesce(p_limit,25),100)) offset greatest(coalesce(p_offset,0),0)) q;
  return jsonb_build_object('items',v_items,'total',v_total);
end $$;

create or replace function public.g4os_list_tasks(p_actor_id uuid,p_project_id uuid,p_status text,p_search text,p_limit integer)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_items jsonb;v_term text:='%'||coalesce(btrim(p_search),'')||'%';
begin
  perform private.g4os_assume_actor(p_actor_id);
  select coalesce(jsonb_agg(to_jsonb(q) order by q.due_at asc nulls last),'[]'::jsonb) into v_items from (select pt.id,pt.project_id,pt.title,pt.description,pt.responsible_role,pt.responsible_name,pt.due_at,pt.status,pt.completed_at,p.reference,p.status as project_status,c.legal_name as company from public.project_tasks pt join public.projects p on p.id=pt.project_id left join public.clients c on c.id=p.client_id where p.deleted_at is null and (p_project_id is null or pt.project_id=p_project_id) and (coalesce(btrim(p_status),'')='' or pt.status::text=p_status) and (coalesce(btrim(p_search),'')='' or pt.title ilike v_term or pt.responsible_name ilike v_term or pt.responsible_role ilike v_term or p.reference ilike v_term or c.legal_name ilike v_term) order by pt.due_at asc nulls last limit greatest(1,least(coalesce(p_limit,25),100))) q;
  return jsonb_build_object('items',v_items);
end $$;

create or replace function public.g4os_rotate_connection(p_owner_user_id uuid,p_label text,p_token_hash text,p_token_prefix text,p_scopes text[],p_rotate boolean)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_active_id uuid;v_row public.contagem_g4os_connections%rowtype;
begin
  if p_scopes is null or cardinality(p_scopes)<1 or exists(select 1 from unnest(p_scopes) scope where scope not in ('read','write')) then raise exception 'Escopos inválidos.';end if;
  if not exists(select 1 from public.profiles where id=p_owner_user_id and active) then raise exception 'Usuário inativo ou inexistente.';end if;
  select id into v_active_id from public.contagem_g4os_connections where owner_user_id=p_owner_user_id and active for update;
  if v_active_id is not null and not p_rotate then raise exception 'Já existe uma conexão ativa.';end if;
  if v_active_id is not null then update public.contagem_g4os_connections set active=false,revoked_at=now() where id=v_active_id;end if;
  insert into public.contagem_g4os_connections(owner_user_id,label,token_hash,token_prefix,scopes) values(p_owner_user_id,coalesce(nullif(btrim(p_label),''),'G4 OS'),p_token_hash,p_token_prefix,to_jsonb(p_scopes)) returning * into v_row;
  return to_jsonb(v_row);
end $$;

revoke all on function private.field_value_present(jsonb) from public,anon,authenticated;
revoke all on function private.assert_request_custom_fields(jsonb,boolean,text,text,text,text,text) from public,anon,authenticated;
revoke all on function private.assert_existing_project_required_fields(uuid) from public,anon,authenticated;
revoke all on function private.validate_project_required_fields_trigger() from public,anon,authenticated;
revoke all on function private.validate_project_field_value_trigger() from public,anon,authenticated;
revoke all on function private.stamp_custom_field_required_from() from public,anon,authenticated;
revoke all on function private.guard_system_custom_field_update() from public,anon,authenticated;
revoke all on function private.guard_profile_active_change() from public,anon,authenticated;
revoke all on function private.guard_last_admin_role() from public,anon,authenticated;
revoke all on function private.guard_last_admin_profile() from public,anon,authenticated;

-- Exclusividade service_role para novos wrappers.
do $$ declare r record;begin for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'g4os_%' loop execute format('revoke all on function %s from public,anon,authenticated',r.signature);execute format('grant execute on function %s to service_role',r.signature);end loop;end $$;
