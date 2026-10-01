-- Convites exigem definição de senha individual no primeiro acesso.
alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

comment on column public.profiles.must_change_password is
  'Quando verdadeiro, bloqueia o uso da plataforma até o usuário definir sua própria senha.';
