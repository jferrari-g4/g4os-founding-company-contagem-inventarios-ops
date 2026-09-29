-- As funções-base de rascunho retornam void. Os wrappers também devem retornar void.
drop function if exists public.g4os_save_dimensioning_draft(uuid,uuid,jsonb,uuid,timestamptz[],text);
create function public.g4os_save_dimensioning_draft(p_actor_id uuid,p_project_id uuid,p_options jsonb,p_selected_option_id uuid,p_visit_starts timestamptz[],p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  perform private.g4os_assume_actor(p_actor_id);
  perform public.save_dimensioning_draft(p_project_id,p_options,p_selected_option_id,p_visit_starts,p_notes);
end;
$$;

drop function if exists public.g4os_save_ti_validation_draft(uuid,uuid,text,text,text,text,text,uuid);
create function public.g4os_save_ti_validation_draft(p_actor_id uuid,p_project_id uuid,p_system_name text,p_ti_contact_name text,p_ti_contact_email text,p_ti_contact_phone text,p_notes text,p_selected_date_option_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  perform private.g4os_assume_actor(p_actor_id);
  perform public.save_ti_validation_draft(p_project_id,p_system_name,p_ti_contact_name,p_ti_contact_email,p_ti_contact_phone,p_notes,p_selected_date_option_id);
end;
$$;

revoke all on function public.g4os_save_dimensioning_draft(uuid,uuid,jsonb,uuid,timestamptz[],text) from public,anon,authenticated;
grant execute on function public.g4os_save_dimensioning_draft(uuid,uuid,jsonb,uuid,timestamptz[],text) to service_role;
revoke all on function public.g4os_save_ti_validation_draft(uuid,uuid,text,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.g4os_save_ti_validation_draft(uuid,uuid,text,text,text,text,text,uuid) to service_role;
