-- Diretório interno de pessoas para organizar a equipe por função/cargo.
alter table public.profiles
  add column if not exists job_title text;

comment on column public.profiles.job_title is
  'Cargo ou função organizacional exibida no diretório interno da operação.';
