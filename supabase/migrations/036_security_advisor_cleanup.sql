-- Remove exposição desnecessária de helper usado por RLS sem alterar seu comportamento.
create or replace function public.is_authenticated()
returns boolean language sql stable security invoker set search_path=public,pg_catalog as $$
  select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and active)
$$;
