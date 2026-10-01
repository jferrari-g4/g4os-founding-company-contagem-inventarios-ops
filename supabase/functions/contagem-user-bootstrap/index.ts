import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedEmails = new Set([
  "balbino@contageminventarios.com.br",
  "estoque@contandoporvoce.com.br",
  "simonsen@contandoporvoce.com.br",
]);
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return json({ error: "Ambiente incompleto." }, 500);
  const db = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });

  const presentedHash = await sha256(req.headers.get("x-bootstrap-secret") || "");
  const credential = await db
    .from("contagem_user_bootstrap_credentials")
    .select("id")
    .eq("secret_hash", presentedHash)
    .eq("active", true)
    .limit(1)
    .maybeSingle();
  if (credential.error || !credential.data?.id) return json({ error: "Credencial interna inválida ou já utilizada." }, 401);

  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: "JSON inválido." }, 400); }
  const emails = Array.isArray(body.emails) ? [...new Set(body.emails.map((item: unknown) => String(item).trim().toLowerCase()))] : [];
  if (emails.length !== 3 || emails.some((email) => !allowedEmails.has(email))) {
    return json({ error: "Lote de bootstrap não autorizado." }, 403);
  }

  const listed = await db.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (listed.error) return json({ error: "Falha ao consultar usuários." }, 500);
  const knownUsers = new Map((listed.data.users || []).map((user) => [String(user.email || "").toLowerCase(), user]));
  const results: Array<Record<string, unknown>> = [];

  try {
    const actor = await db.from("profiles").select("id").eq("email", "j.ferrari@g4educacao.com").maybeSingle();
    for (const email of emails) {
      let user = knownUsers.get(email);
      let invited = false;
      if (!user) {
        const invitation = await db.auth.admin.inviteUserByEmail(email, { data: { full_name: email } });
        if (invitation.error || !invitation.data.user) throw invitation.error || new Error(`Convite não criado para ${email}.`);
        user = invitation.data.user;
        invited = true;
      }

      const profile = await db.from("profiles").upsert({
        id: user.id,
        full_name: email,
        email,
        job_title: null,
        active: true,
        must_change_password: true,
      }, { onConflict: "id" });
      if (profile.error) throw profile.error;

      const clearRoles = await db.from("user_roles").delete().eq("user_id", user.id);
      if (clearRoles.error) throw clearRoles.error;
      const adminRole = await db.from("user_roles").insert({ user_id: user.id, role: "admin" });
      if (adminRole.error) throw adminRole.error;

      await db.from("audit_logs").insert({
        entity: "profiles",
        entity_id: user.id,
        action: invited ? "user_invited_api" : "user_access_bootstrapped_api",
        after_data: { email, roles: ["admin"], must_change_password: true },
        actor_id: actor.data?.id || null,
      });
      results.push({ email, user_id: user.id, invited, active: true, roles: ["admin"], must_change_password: true });
    }

    const consumed = await db.rpc("finish_contagem_user_bootstrap", { p_credential_id: credential.data.id });
    if (consumed.error) throw consumed.error;
    return json({ status: "success", users: results });
  } catch (error) {
    return json({ status: "failed", completed: results, error: error instanceof Error ? error.message : "Falha no bootstrap." }, 500);
  }
});
