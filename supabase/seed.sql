-- Dados iniciais. Executar após as migrations.
insert into public.planning_block_definitions(block_key,label,description,sort_order,required_for_completion) values
('store','Informações da loja','Unidade, períodos de pré-contagem e inventário, efetivo geral.',10,true),
('responsibilities','Responsáveis pela operação','Funções e responsáveis configuráveis.',20,true),
('logistics','Logística','Transporte, hospedagem e observações gerais.',30,false),
('client_equipment','Equipamentos do cliente','Necessidades acordadas com o cliente, por dia e turno.',40,false),
('contagem_equipment','Equipamentos Contagem','Recursos próprios por dia e turno.',50,false),
('pre_count','Pré-contagem','Datas, horários, equipe, quantidade e observações.',60,false),
('inventory_days','Dias de inventário','Áreas, turnos, equipes e atividades dinâmicas.',70,true),
('checklists','Checklists','Planejamento e conferência final obrigatória.',80,true)
on conflict(block_key) do update set label=excluded.label,description=excluded.description,sort_order=excluded.sort_order,required_for_completion=excluded.required_for_completion;

insert into public.custom_fields(entity,field_key,label,field_type,required,active,sort_order,system_field) values
('project','inventory_type','Tipo de inventário','select',true,true,10,true),
('project','layout_system','Layout / sistema','text',true,true,20,true),
('project','ti_contact_name','Contato da TI — nome','text',true,true,30,true),
('project','ti_contact_email','Contato da TI — e-mail','email',true,true,40,true),
('project','ti_contact_phone','Contato da TI — telefone','phone',false,true,50,true)
on conflict(field_key) do update set label=excluded.label,required=excluded.required,active=excluded.active,system_field=excluded.system_field;

insert into public.equipment_catalog(owner_type,name) values
('client','Empilhadeira'),('client','Escada'),('client','Balança'),('client','Paleteira'),
('contagem','Escada'),('contagem','EPI perecível'),('contagem','Coletor'),('contagem','Rádio')
on conflict(owner_type,name) do nothing;

insert into public.checklist_templates(name,checklist_type,inventory_type) values
('Visita Pré-Inventário padrão','pre_inventory_visit',null),
('Planejamento padrão','planning',null)
on conflict do nothing;

insert into public.checklist_template_items(template_id,label,required,sort_order)
select t.id,v.label,true,v.sort_order from public.checklist_templates t cross join (values
('Aplicar Checklist Fácil',10),('Alinhar com gerência o horário de início',20),('Definir horários de alimentação',30),('Identificar pendências da loja',40),('Validar áreas de estoque e piso de vendas',50),('Confirmar coleta das gavetas',60),('Alinhar início do piso de vendas',70),('Confirmar necessidade de efetivo adicional',80),('Confirmar disponibilidade de equipamentos e apoio da loja',90)
) as v(label,sort_order) where t.name='Visita Pré-Inventário padrão'
and not exists (select 1 from public.checklist_template_items i where i.template_id=t.id and i.label=v.label);

-- Após criar o primeiro usuário, execute uma vez e substitua o e-mail:
-- insert into public.user_roles(user_id,role) select id,'admin' from public.profiles where email='admin@contandoporvoce.com.br' on conflict do nothing;
