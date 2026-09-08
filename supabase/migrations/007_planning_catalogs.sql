-- Catálogos administráveis usados pelos blocos de planejamento.
create table public.planning_role_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  category text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create table public.planning_activity_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  area_type text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.planning_role_catalog enable row level security;
alter table public.planning_activity_catalog enable row level security;
create policy planning_role_catalog_read on public.planning_role_catalog for select using (public.is_authenticated());
create policy planning_role_catalog_admin_manage on public.planning_role_catalog for all using (private.is_admin()) with check (private.is_admin());
create policy planning_activity_catalog_read on public.planning_activity_catalog for select using (public.is_authenticated());
create policy planning_activity_catalog_admin_manage on public.planning_activity_catalog for all using (private.is_admin()) with check (private.is_admin());

insert into public.planning_role_catalog(name,category,sort_order) values
('Liderança geral','Liderança',10),('Mesa','Liderança',20),('Frios','Liderança',30),('Líder de pré-contagem','Liderança',40),('Coordenação do turno noturno','Liderança',50),('Coordenador líder','Equipe',60),('Coordenador','Equipe',70),('Apoio','Equipe',80),('Conferente','Equipe',90),('Líder de perecíveis','Equipe',100)
on conflict(name) do nothing;
insert into public.planning_activity_catalog(name,area_type,sort_order) values
('Coleta das gavetas','Depósito',10),('Coleta de picking','Depósito',20),('Coleta de aéreo','Depósito',30),('Coleta de subaéreo','Depósito',40),('Coleta de aéreo','Câmaras',50),('Coleta de subaéreo','Câmaras',60),('Coleta de picking','Câmaras',70),('Coleta de produtos para pesagem/balança','Câmaras',80),('Mapeamento do piso de vendas','Geral',90),('Auditoria e ajuste das gavetas','Geral',100)
on conflict(name) do nothing;
