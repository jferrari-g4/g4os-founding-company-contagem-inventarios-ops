-- Gates operacionais por papel: dimensionamento e validação de TI.
create or replace function public.complete_dimensioning(p_project_id uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if not (private.has_role('admin') or private.has_role('operational') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas a operação pode concluir o dimensionamento.';
  end if;
  if not exists(select 1 from public.projects where id=p_project_id and status='awaiting_dimensioning' and deleted_at is null) then
    raise exception 'O projeto não está aguardando dimensionamento.';
  end if;
  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  update public.dimensionings set status='approved',completed_at=now(),approved_by=auth.uid(),approved_at=now(),notes=coalesce(p_notes,notes) where project_id=p_project_id;
  update public.projects set status='awaiting_ti',operational_notes=coalesce(p_notes,operational_notes),updated_by=auth.uid(),updated_at=now() where id=p_project_id;
end;
$$;

create or replace function public.approve_ti_validation(p_project_id uuid,p_system_name text default null,p_notes text default null)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if not (private.has_role('admin') or private.has_role('ti') or private.has_role('operational_supervisor') or private.has_role('operational_manager')) then
    raise exception 'Apenas TI ou gestores autorizados podem validar o projeto.';
  end if;
  if not exists(select 1 from public.projects where id=p_project_id and status='awaiting_ti' and deleted_at is null) then
    raise exception 'O projeto não está aguardando validação de TI.';
  end if;
  perform set_config('app.secure_operational_gate',p_project_id::text,true);
  insert into public.ti_validations(project_id,status,system_name,notes,validated_by,validated_at)
  values(p_project_id,'approved',p_system_name,p_notes,auth.uid(),now())
  on conflict(project_id) do update set status='approved',system_name=coalesce(excluded.system_name,public.ti_validations.system_name),notes=coalesce(excluded.notes,public.ti_validations.notes),validated_by=auth.uid(),validated_at=now();
  insert into public.plannings(project_id,status,started_by) values(p_project_id,'in_progress',auth.uid()) on conflict(project_id) do update set status=case when public.plannings.status in ('draft','in_progress') then 'in_progress' else public.plannings.status end;
  update public.projects set status='planning',updated_by=auth.uid(),updated_at=now() where id=p_project_id;
end;
$$;

create or replace function private.guard_operational_gate_status()
returns trigger language plpgsql security definer set search_path=public,private,pg_catalog as $$
begin
  if new.status in ('awaiting_ti','planning') and old.status is distinct from new.status then
    if current_setting('app.secure_operational_gate',true) is distinct from new.id::text then
      raise exception 'Use a operação protegida para avançar este gate operacional.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_operational_gate_status on public.projects;
create trigger guard_operational_gate_status before update on public.projects for each row execute function private.guard_operational_gate_status();
revoke all on function public.complete_dimensioning(uuid,text) from public,anon;
revoke all on function public.approve_ti_validation(uuid,text,text) from public,anon;
grant execute on function public.complete_dimensioning(uuid,text) to authenticated;
grant execute on function public.approve_ti_validation(uuid,text,text) to authenticated;
