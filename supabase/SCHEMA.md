# Snapshot do schema do banco

Gerado em **06/10/2026 às 23:54 (America/Sao_Paulo)** para preparar a futura migração da Contagem OPS.

## Conteúdo versionado

- `schema.sql`: ponto único de reprodução do schema, encadeando as **43 migrations** na ordem correta.
- `migrations/`: histórico completo e fonte canônica das mudanças.
- `seed.sql`: dados iniciais controlados, aplicado separadamente quando necessário.

## Cobertura validada no banco atual

| Objeto | Quantidade |
|---|---:|
| Tabelas (`public` + `private`) | 51 |
| Enums | 9 |
| Funções | 65 |
| Políticas RLS | 92 |
| Índices | 107 |
| Gatilhos não internos | 22 |
| Views | 0 |
| Migrations aplicadas | 43 |

## O que não está neste snapshot

- Dados operacionais das tabelas.
- Usuários, identidades e sessões do Supabase Auth.
- Tokens MCP, OAuth ou credenciais em texto aberto.
- Conteúdo do Supabase Vault.
- Edge Function Secrets.
- Configuração e variáveis da Vercel.

## Procedimento seguro de migração

1. Criar e autorizar o projeto Supabase de destino.
2. Substituir referências ao projeto atual `racxkiswyjilfnzwmzqb` nas migrations/funções de cron pelo novo projeto.
3. Aplicar `schema.sql` em banco vazio com parada no primeiro erro.
4. Recriar os segredos no Vault e nas Edge Functions pelo cofre seguro.
5. Publicar as Edge Functions do diretório `functions/`.
6. Migrar dados preservando IDs e relacionamentos.
7. Recriar usuários do Auth por convite/redefinição de senha; não exportar senhas.
8. Validar RLS, advisors, funções, cron e contagens antes do corte.

## Execução

A partir da raiz do repositório:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/schema.sql
```

O `schema.sql` usa `\ir`, portanto deve ser executado a partir da raiz do repositório. Não execute em produção sem revisar os jobs transitórios das migrations `031` e `043`.
