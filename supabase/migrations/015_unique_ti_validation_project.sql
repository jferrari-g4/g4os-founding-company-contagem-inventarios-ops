-- Permite atualizar a validação de TI por projeto com upsert seguro.
-- Não há duplicidades existentes na tabela ti_validations no momento da aplicação.
alter table public.ti_validations
  add constraint ti_validations_project_id_key unique (project_id);
