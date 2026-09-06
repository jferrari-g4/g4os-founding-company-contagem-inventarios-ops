# Módulo de planejamento — requisitos consolidados

Fonte: instruções de planejamento e modelo Assaí Feira de Santana recebidos em 27 de agosto de 2026.

## Princípios

- O planejamento é editável por blocos e pode permanecer incompleto.
- O sistema exibe percentual de completude e pendências por bloco.
- Todas as tabelas operacionais permitem adicionar/remover linhas; exclusão preserva auditoria.
- O usuário pode avançar e voltar entre etapas sem perder dados.
- Cada alteração deve ter usuário, data/hora, antes/depois e versão registrados.
- Visual responsivo: computador é a experiência principal; celular atende consulta e atualizações rápidas.

## Blocos funcionais

1. **Informações da loja:** unidade, período de pré-contagem opcional, um ou mais dias de inventário e efetivo geral previsto.
2. **Responsáveis:** tabela de função e responsável; funções vêm de cadastro administrável e novas linhas podem ser incluídas.
3. **Logística:**
   - transporte: data, trajeto, passageiros, quantidade e observações;
   - hospedagem: hóspedes, quartos, entrada, saída e quantidade de hóspedes;
   - observações gerais extensas.
4. **Equipamentos do cliente:** lista/tabela com equipamento, dia, turno, quantidade, status e observação; detalhes livres.
5. **Equipamentos Contagem:** mesma estrutura, com catálogo próprio (escadas, EPIs perecíveis etc.) e detalhes livres.
6. **Pré-contagem:** linhas de data, horário, equipe, quantidade e observação; detalhes livres.
7. **Dias de inventário:** o usuário adiciona tantos dias quanto necessário. Cada dia tem data, efetivo previsto e sub-blocos configuráveis.
   - depósito: início, equipe, liderança e atividades por linha;
   - câmaras: início, equipe, liderança e atividades por linha;
   - outros turnos/áreas podem ser adicionados.
8. **Coordenação e divisão de equipe:** responsável/local, função, quantidade, nomes e observações. Pode existir em qualquer dia do inventário.

## Checklists

- **Visita pré-inventário:** recomendada três dias antes e obrigatória até um dia antes; ao concluir, fecha a etapa de visita.
- **Checklist de planejamento:** itens configuráveis por tipo de inventário; mostra total confirmado e pendências.
- Todo item possui responsável, status, observação e evidência opcional.

## Fluxo

1. Dimensionamento aprovado e validação TI concluída liberam o planejamento.
2. Planejamento é iniciado como rascunho e recebe dados de cliente, unidade, opções aprovadas e datas confirmadas.
3. Supervisor operacional e gestores editam os blocos e acompanham completude.
4. Checklist e aprovações liberam o planejamento para publicação.
5. Publicação gera PDF no modelo aprovado e envia/cadastra no Notion.

## Exemplo de dados que precisam ser suportados

O modelo Assaí contém pré-contagem em quatro dias, transporte/hospedagem com múltiplas linhas, visita pré-inventário, demandas de empilhadeiras por turno, dois dias de inventário, depósito, câmaras, turno tarde, turno noturno, coordenação, divisão de equipe e checklist com 17 itens. O modelo confirma que dia/turno não pode ser um campo único fixo.

## Dependências para concluir o módulo

- Modelo final de PDF.
- Lista inicial de funções, atividades e equipamentos para os cadastros.
- Definição dos itens do checklist de planejamento.
- Integração/credenciais do Notion e regra de pasta/página de publicação.
