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

Sem variáveis Supabase, a interface opera em modo demonstração com `localStorage`. Para produção, configure as variáveis, aplique `supabase/migrations/001_initial_schema.sql` no Supabase e implemente as políticas RLS por perfil.

## Vercel

1. Importe o repositório no Vercel.
2. Configure as variáveis de `.env.example`.
3. Faça deploy. A função `/api/cnpj` já consulta a BrasilAPI pelo servidor.
4. Configure `CRON_SECRET` para a rota de alerta de dimensionamento; o job roda de hora em hora conforme `vercel.json`.

## Observações de produção

- E-mail exige provedor configurado (Resend/SMTP); Slack exige Webhook por canal.
- Não coloque `SUPABASE_SERVICE_ROLE_KEY` no frontend.
- O PDF e a publicação no Notion serão implementados após o modelo final de PDF e as credenciais/API do Notion serem fornecidos.
