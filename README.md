# Contagem Ops Platform

MVP da POC 01 para abertura comercial, cadastro de clientes, consulta CNPJ, fila de dimensionamento, validação TI, datas operacionais, planejamento e auditoria.

## Stack acordado

- React + JavaScript (Vite)
- Supabase: Postgres, Auth, RLS e Storage
- Vercel: homologação, funções HTTP e alertas agendados
- GitHub: versionamento e entrega para posterior deploy em VPS

## Rodar localmente

```bash
cp .env.example .env
npm install
npm run dev
```

Sem variáveis Supabase, a interface opera em modo demonstração com `localStorage`.

## Criar o banco no Supabase

1. Crie um projeto Supabase vazio.
2. No SQL Editor, execute as migrations na ordem:
   - `supabase/migrations/001_initial_schema.sql`
   - `supabase/migrations/002_full_operational_model.sql`
   - `supabase/migrations/003_security_refinements.sql`
   - `supabase/migrations/004_planning_block_order.sql`
   - `supabase/migrations/005_harden_database_functions.sql`
   - `supabase/migrations/006_protect_custom_fields.sql`
   - `supabase/migrations/007_planning_catalogs.sql`
3. Execute `supabase/seed.sql` para cadastrar os campos, equipamentos e checklist inicial.
4. Crie o primeiro usuário em **Authentication > Users** e execute o comando comentado no final de `seed.sql` para atribuir o papel `admin`.
5. Copie apenas `Project URL` e a `publishable key` para o frontend como `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`. A `service_role key` fica somente em variáveis de servidor no Vercel/VPS.

O modelo inclui clientes/contatos, solicitações, opções de data, dimensionamentos, validação de TI, planejamento por blocos, checklists, anexos, histórico de auditoria e fila de notificações para e-mail/Slack.

## Vercel

1. Importe o repositório no Vercel.
2. Configure as variáveis de `.env.example`. A interface exige login via Supabase Auth; cadastre o primeiro usuário pela tela e depois atribua o papel `admin` seguindo o comando em `seed.sql`.
3. Faça deploy. A função `/api/cnpj` já consulta a BrasilAPI pelo servidor.
4. O alerta automático de dimensionamento fica preparado no código, mas o agendamento será habilitado em uma etapa posterior para manter a primeira publicação compatível com o plano Hobby.

## Observações de produção

- E-mail exige provedor configurado (Resend/SMTP); Slack exige Webhook por canal.
- Não coloque `SUPABASE_SERVICE_ROLE_KEY` no frontend.
- O PDF e a publicação no Notion serão implementados após o modelo final de PDF e as credenciais/API do Notion serem fornecidos.
