import React, { useEffect, useMemo, useState } from 'react';
import { hasSupabase, supabase } from './supabase';

const endpoint = `${String(import.meta.env.VITE_SUPABASE_URL || '').replace(/\/$/, '')}/functions/v1/contagem-ops-mcp`;

const call = async (action, payload = {}) => {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) throw new Error('Sessão expirada.');

  const response = await fetch(
    `${String(import.meta.env.VITE_SUPABASE_URL || '').replace(/\/$/, '')}/functions/v1/g4os-connections`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        apikey:
          import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
          import.meta.env.VITE_SUPABASE_ANON_KEY ||
          '',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ action, ...payload }),
    },
  );
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || 'Falha na conexão.');
  return body;
};

const copy = (value) => navigator.clipboard.writeText(value);

const buildConnectionPrompt = (mcpEndpoint, scopes) => `Conecte o Contagem OPS a este workspace do G4 OS.

Nome da fonte: Contagem OPS
Slug sugerido: contagem-ops
Tipo: MCP remoto (Streamable HTTP / JSON-RPC)
URL MCP: ${mcpEndpoint}
Autenticação: Bearer
Escopos autorizados nesta credencial: ${scopes.join(' + ')}

Regras obrigatórias:
1. Crie ou atualize uma Source MCP chamada Contagem OPS usando a URL acima.
2. Não peça nem receba o token pelo chat. Abra o cartão privado e seguro de credenciais para eu colar o token Bearer exibido na plataforma.
3. Depois de salvar a credencial, teste a conexão e execute tools/list.
4. Confirme pelo menos as ferramentas contagem_overview, contagem_list_projects, contagem_list_tasks, contagem_list_users e contagem_list_team_assignments.
5. Preserve os escopos, papéis, gates humanos, exclusões lógicas e permissões definidos na plataforma. Não tente alterar código-fonte.
6. Ao final, informe se a fonte ficou ativa e quais grupos de ferramentas estão disponíveis.`;

export default function G4OSConnection() {
  const [state, setState] = useState(null);
  const [secret, setSecret] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [scopeMode, setScopeMode] = useState('read-write');
  const active = useMemo(
    () => state?.connections?.find((item) => item.active) || null,
    [state],
  );

  const reload = async () => {
    if (!hasSupabase) return;
    try {
      setState(await call('list'));
    } catch (error) {
      setMessage(error.message);
    }
  };

  useEffect(() => {
    reload();
  }, []);

  const connect = async (rotate = false) => {
    if (
      rotate &&
      !window.confirm(
        'Rotacionar a credencial atual? O G4 OS conectado deixará de acessar imediatamente.',
      )
    )
      return;

    setBusy(true);
    try {
      const created = await call(rotate ? 'rotate' : 'create', {
        scopes: scopeMode === 'read-only' ? ['read'] : ['read', 'write'],
      });
      setSecret(created);
      setMessage(
        'Credencial criada. Abra o G4 OS e cole o token somente no cartão privado de credenciais.',
      );
      await reload();
    } catch (error) {
      setMessage(error.message);
    } finally {
      setBusy(false);
    }
  };

  const revoke = async () => {
    if (!active || !window.confirm('Revogar esta conexão?')) return;
    setBusy(true);
    try {
      await call('revoke', { connectionId: active.id });
      setSecret(null);
      setMessage('Conexão revogada.');
      await reload();
    } catch (error) {
      setMessage(error.message);
    } finally {
      setBusy(false);
    }
  };

  const connectionPrompt = secret
    ? buildConnectionPrompt(secret.endpoint || state?.endpoint || endpoint, secret.scopes || [])
    : '';

  const openG4OS = () => {
    if (!connectionPrompt) return;
    const deepLink = `g4os://action/new-session?input=${encodeURIComponent(connectionPrompt)}&send=true&mode=execute`;
    window.open(deepLink, '_blank', 'noopener,noreferrer');
  };

  if (!hasSupabase)
    return (
      <section className="card">
        <h2>Conectar ao G4 OS</h2>
        <p>Disponível quando a plataforma estiver conectada ao Supabase e você iniciar sessão.</p>
      </section>
    );

  return (
    <section className="g4os-connection">
      <div className="page-intro">
        <div>
          <span className="eyebrow">Integração segura</span>
          <h2>Conectar Contagem OPS ao G4 OS</h2>
          <p>
            Gere uma credencial individual e abra o G4 OS com o prompt de conexão já preenchido.
            O token continua protegido e é inserido somente no cartão privado de credenciais.
          </p>
        </div>
        <span className={`connection-status ${active ? 'is-active' : ''}`}>
          {active ? 'Conectada' : 'Não conectada'}
        </span>
      </div>

      {message && (
        <div className="notice" role="status">
          {message}
        </div>
      )}

      <div className="g4os-grid">
        <article className="card">
          <h3>Conexão guiada</h3>
          <ol>
            <li>Escolha o nível de acesso e gere sua conexão individual.</li>
            <li>Clique em Abrir no G4 OS para iniciar uma sessão com o prompt pronto.</li>
            <li>Cole o token somente no cartão privado solicitado pelo G4 OS.</li>
            <li>O G4 OS cadastra, testa e confirma as ferramentas disponíveis.</li>
          </ol>

          <label className="connection-field">
            URL MCP
            <div>
              <code>{state?.endpoint || endpoint}</code>
              <button onClick={() => copy(state?.endpoint || endpoint)}>Copiar</button>
            </div>
          </label>

          {secret && (
            <>
              <label className="connection-field secret">
                Token Bearer — exibição única
                <div>
                  <code>{secret.token}</code>
                  <button onClick={() => copy(secret.token)}>Copiar token</button>
                </div>
              </label>
              <p className="hint">
                Não envie esse token por mensagem, e-mail ou prompt. Use apenas o cartão privado de
                credenciais aberto pelo G4 OS.
              </p>
              <div className="g4os-open-actions">
                <button className="primary" type="button" onClick={openG4OS}>
                  Abrir no G4 OS
                </button>
                <button type="button" onClick={() => copy(connectionPrompt)}>
                  Copiar prompt
                </button>
              </div>
              <p className="hint">
                Se o aplicativo não abrir automaticamente, copie o prompt e envie em uma nova sessão
                do G4 OS. O prompt não contém o token.
              </p>
            </>
          )}
        </article>

        <article className="card">
          <h3>Ferramentas disponíveis</h3>
          <ul className="tool-list">
            <li>
              <b>Visão e consultas</b>
              <span>Operações, detalhes, calendário, tarefas e diretório de pessoas.</span>
            </li>
            <li>
              <b>Operação e equipes</b>
              <span>Tarefas, solicitações, planejamento e alocações conforme perfil.</span>
            </li>
            <li>
              <b>Administração</b>
              <span>Usuários, acessos, campos e catálogos somente para administradores.</span>
            </li>
          </ul>
          <p className="hint">
            Gates de dimensionamento, TI e aprovação continuam protegidos pela plataforma.
          </p>
        </article>
      </div>

      {!active && !secret && (
        <div className="connection-create">
          <label>
            Nível de acesso
            <select value={scopeMode} onChange={(event) => setScopeMode(event.target.value)}>
              <option value="read-only">Somente leitura</option>
              <option value="read-write">Leitura e escrita conforme meu perfil</option>
            </select>
          </label>
          <button className="primary" disabled={busy} onClick={() => connect(false)}>
            {busy ? 'Gerando…' : 'Gerar conexão individual'}
          </button>
        </div>
      )}

      {active && (
        <div className="connection-actions">
          <div>
            <b>Credencial ativa: {active.token_prefix}</b>
            <span>Escopos: {(active.scopes || []).join(' + ')}</span>
            <span>
              Último uso:{' '}
              {active.last_used_at
                ? new Date(active.last_used_at).toLocaleString('pt-BR')
                : 'ainda não utilizada'}
            </span>
          </div>
          <select
            aria-label="Escopos da nova credencial"
            value={scopeMode}
            onChange={(event) => setScopeMode(event.target.value)}
          >
            <option value="read-only">Somente leitura</option>
            <option value="read-write">Leitura + escrita</option>
          </select>
          <button disabled={busy} onClick={() => connect(true)}>
            Rotacionar
          </button>
          <button className="delete" disabled={busy} onClick={revoke}>
            Revogar
          </button>
        </div>
      )}

      {state?.events?.length > 0 && (
        <article className="card connection-events">
          <h3>Auditoria recente</h3>
          {state.events.map((event) => (
            <div key={event.id}>
              <b>{event.tool_name}</b>
              <span>
                {event.operation} · {event.success ? 'sucesso' : 'falha'} ·{' '}
                {new Date(event.occurred_at).toLocaleString('pt-BR')}
              </span>
            </div>
          ))}
        </article>
      )}
    </section>
  );
}
