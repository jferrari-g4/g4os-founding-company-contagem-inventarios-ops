-- Campos-base não podem ser apagados; campos personalizados só podem ser apagados sem uso.
alter table public.custom_fields add column if not exists system_field boolean not null default false;
update public.custom_fields set system_field=true where field_key in ('inventory_type','layout_system','ti_contact_name','ti_contact_email','ti_contact_phone');

create or replace function public.prevent_custom_field_deletion() returns trigger language plpgsql set search_path=public,pg_catalog as $$
begin
  if old.system_field then
    raise exception 'Campos-base não podem ser excluídos.';
  end if;
  if exists(select 1 from public.project_field_values where field_id=old.id) then
    raise exception 'Este campo já possui dados preenchidos e não pode ser excluído.';
  end if;
  return old;
end;
$$;

drop trigger if exists custom_fields_prevent_delete on public.custom_fields;
create trigger custom_fields_prevent_delete before delete on public.custom_fields for each row execute procedure public.prevent_custom_field_deletion();
revoke all on function public.prevent_custom_field_deletion() from public, anon, authenticated;
