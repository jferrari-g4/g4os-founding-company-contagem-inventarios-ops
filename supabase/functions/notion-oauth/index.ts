import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const NOTION_VERSION = "2026-03-11";
const REDIRECT_URI = "https://racxkiswyjilfnzwmzqb.supabase.co/functions/v1/notion-oauth/callback";

const html = (title: string, message: string, status = 200) =>
  new Response(`<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{margin:0;background:#f6f7f8;color:#242323;font-family:Inter,Arial,sans-serif;display:grid;min-height:100vh;place-items:center}.card{width:min(560px,calc(100% - 40px));background:#fff;border:1px solid #e4e5e7;border-radius:18px;padding:32px;box-shadow:0 18px 55px rgba(36,35,35,.08)}.brand{font-size:12px;font-weight:900;letter-spacing:.12em;color:#EC2226}.status{display:inline-block;margin-top:20px;border-radius:99px;background:#e8f7ee;color:#18733d;padding:7px 10px;font-size:12px;font-weight:800}h1{font-size:28px;margin:14px 0 10px}p{color:#676b72;line-height:1.6;margin:0}</style></head><body><main class="card"><div class="brand">CONTAGEM OPS</div><span class="status">${status < 400 ? "CONEXÃO SEGURA" : "ATENÇÃO"}</span><h1>${title}</h1><p>${message}</p></main></body></html>`, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
};

const randomState = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
};

Deno.serve(async (req) => {
  if (req.method !== "GET") return html("Método não permitido", "Use o fluxo de autorização iniciado pela plataforma.", 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const clientId = Deno.env.get("NOTION_OAUTH_CLIENT_ID");
  const clientSecret = Deno.env.get("NOTION_OAUTH_CLIENT_SECRET");
  if (!supabaseUrl || !serviceKey) return html("Ambiente incompleto", "A infraestrutura da conexão ainda não está disponível.", 503);

  const db = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const url = new URL(req.url);
  const callback = url.pathname.endsWith("/callback");

  if (!callback) {
    if (!clientId) return html("OAuth ainda não configurado", "Cadastre primeiro o Client ID do Notion nos segredos da função.", 503);
    const state = randomState();
    await db.from("notion_oauth_states").delete().lt("expires_at", new Date().toISOString());
    const stored = await db.from("notion_oauth_states").insert({
      state_hash: await sha256(state),
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });
    if (stored.error) return html("Não foi possível iniciar", "Falha ao criar a autorização segura. Tente novamente.", 500);

    const authorization = new URL("https://api.notion.com/v1/oauth/authorize");
    authorization.searchParams.set("owner", "user");
    authorization.searchParams.set("client_id", clientId);
    authorization.searchParams.set("redirect_uri", REDIRECT_URI);
    authorization.searchParams.set("response_type", "code");
    authorization.searchParams.set("state", state);
    return Response.redirect(authorization.toString(), 302);
  }

  const oauthError = url.searchParams.get("error");
  if (oauthError) return html("Autorização cancelada", "O Notion não concedeu acesso. Nenhum dado foi importado.", 400);
  if (!clientId || !clientSecret) return html("OAuth ainda não configurado", "Client ID ou Client Secret ausente no cofre do Supabase.", 503);

  const code = url.searchParams.get("code") || "";
  const state = url.searchParams.get("state") || "";
  if (!code || !state) return html("Resposta inválida", "O código ou o estado de segurança não foi recebido.", 400);

  const consumed = await db
    .from("notion_oauth_states")
    .delete()
    .eq("state_hash", await sha256(state))
    .gte("expires_at", new Date().toISOString())
    .select("state_hash")
    .maybeSingle();
  if (consumed.error || !consumed.data) return html("Autorização expirada", "Inicie novamente a conexão para gerar um estado de segurança válido.", 400);

  const tokenResponse = await fetch("https://api.notion.com/v1/oauth/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
      "Content-Type": "application/json",
      "Notion-Version": NOTION_VERSION,
    },
    body: JSON.stringify({ grant_type: "authorization_code", code, redirect_uri: REDIRECT_URI }),
  });
  const token = await tokenResponse.json().catch(() => ({}));
  if (!tokenResponse.ok || !token.access_token) return html("Falha ao concluir OAuth", "O Notion recusou a troca do código. Gere uma nova autorização.", 502);

  const storedTokens = await db.rpc("store_notion_oauth_tokens", {
    p_access_token: token.access_token,
    p_refresh_token: token.refresh_token || "",
  });
  if (storedTokens.error) return html("Falha ao proteger credenciais", "Os tokens não puderam ser armazenados no cofre seguro.", 500);

  const metadata = await db.from("notion_oauth_authorizations").upsert(
    {
      workspace_id: token.workspace_id,
      workspace_name: token.workspace_name || null,
      workspace_icon: token.workspace_icon || null,
      bot_id: token.bot_id,
      notion_owner_id: token.owner?.user?.id || null,
      active: true,
      connected_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "workspace_id" },
  );
  if (metadata.error) return html("Conexão parcial", "A credencial foi protegida, mas os metadados do workspace não foram salvos.", 500);

  const workspace = String(token.workspace_name || "Contagem").replace(/[<>&"']/g, "");
  return html("Notion conectado", `O workspace ${workspace} foi autorizado com sucesso. Você já pode fechar esta página e executar o dry-run na Contagem OPS.`);
});
