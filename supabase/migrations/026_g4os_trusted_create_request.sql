-- Bridge exclusivo do service_role para o MCP. A identidade do dono da conexão
-- é injetada apenas dentro da transação para reutilizar os gates de criação existentes.
create or replace function public.g4os_create_project_request(
  p_actor_id uuid,p_request_key uuid,p_cnpj text,p_cnpj_raw text,p_legal_name text,p_trade_name text,p_address text,
  p_contact_name text,p_contact_email text,p_contact_phone text,p_inventory_type text,p_layout_system text,
  p_ti_contact_name text,p_ti_contact_email text,p_ti_contact_phone text,p_requires_dimensioning boolean,
  p_operational_notes text,p_field_values jsonb,p_planning_content jsonb
) returns uuid language plpgsql security definer set search_path=public,private,pg_catalog as $$
declare v_project_id uuid;
begin
  if p_actor_id is null then raise exception 'Ator G4 OS obrigatório.'; end if;
  perform set_config('request.jwt.claim.sub',p_actor_id::text,true);
  select public.create_project_request(p_request_key,p_cnpj,p_cnpj_raw,p_legal_name,p_trade_name,p_address,p_contact_name,p_contact_email,p_contact_phone,p_inventory_type,p_layout_system,p_ti_contact_name,p_ti_contact_email,p_ti_contact_phone,p_requires_dimensioning,p_operational_notes,p_field_values,p_planning_content) into v_project_id;
  return v_project_id;
end;
$$;
revoke all on function public.g4os_create_project_request(uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.g4os_create_project_request(uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean,text,jsonb,jsonb) to service_role;
