-- Controla a visibilidade de campos conforme a solicitação exige dimensionamento.
alter table public.custom_fields
  add column if not exists show_when_dimensioning boolean not null default false;

update public.custom_fields
set show_when_dimensioning = true
where field_key in ('layout_system','ti_contact_name','ti_contact_email','ti_contact_phone');
