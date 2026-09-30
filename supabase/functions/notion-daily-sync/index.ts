import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type Row = Record<string, any>;
type Source = {
  id: string;
  source_key: string;
  title: string;
  database_id: string;
  data_source_id: string | null;
  target_kind: string;
  import_pii: boolean;
  last_successful_sync_at: string | null;
  resume_cursor: string | null;
  resume_mode: "full" | "incremental" | null;
  resume_since: string | null;
  resume_started_at: string | null;
  full_sync_completed_at: string | null;
  checkpoint_version: number;
};
type SyncInput = { source_keys?: string[]; full?: boolean; dry_run?: boolean; page_size?: number; max_pages_per_source?: number };

const NOTION_VERSION = "2026-03-11";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type,x-cron-secret",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const clamp = (value: unknown, fallback: number, min: number, max: number) => Math.max(min, Math.min(max, Number(value) || fallback));
const normalize = (value: unknown) => String(value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "");
const digits = (value: unknown) => String(value ?? "").replace(/\D/g, "");
const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
};

const ALLOWLISTS: Record<string, Set<string>> = {
  agendamento: new Set(["nos", "numeroos", "os", "inventario", "status", "cnpjclientefilialloja", "cliente", "cadastrocliente", "clienteloja", "filialloja", "tipodeinventario", "equipetotal", "tequipe"]),
  cadastro_clientes: new Set(["cnpj", "cliente", "razaosocial", "filialloja", "clienteloja", "endereco", "cidade", "estado", "codigo"]),
  tarefas: new Set(["idtarefa", "descricaotarefa", "tarefa", "tipo", "prazodias"]),
  tarefas_em_desenvolvimento: new Set(["codinv", "nos", "os", "tarefa", "descricao", "status", "inicio", "prazo", "datalimite"]),
  coletores: new Set(["patrimonio", "modelo", "filial", "localizacao", "disponivel", "ativo"]),
  pops: new Set(["descricao", "descricaoresumida", "status", "setorarea", "tipo", "categoria", "linkdodocumento", "link", "url"]),
  processos_internos: new Set(["descricao", "descricaoresumida", "status", "setorarea", "tipo", "categoria", "linkdodocumento", "link", "url"]),
};
const REDACT_CONTENT = /(senha|password|secret|token|cpf|\brg\b|chave\s*pix|dados?\s*banc|conta\s*banc|ag[eê]ncia\s*banc)/i;
const CPF_PATTERN = /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/;
const EMAIL_PATTERN = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;
const PHONE_PATTERN = /(?:\+?55\s*)?(?:\(?\d{2}\)?[\s.-]*)?\d{4,5}[\s.-]*\d{4}/;

function scrubString(value: string, detectPhone = true) {
  return REDACT_CONTENT.test(value) || CPF_PATTERN.test(value) || EMAIL_PATTERN.test(value) || (detectPhone && PHONE_PATTERN.test(value)) ? "[REDACTED]" : value;
}
function canonicalNotionUrl(pageId: string) { return `https://www.notion.so/${pageId.replace(/-/g, "")}`; }
function scrubJson(value: Json, detectPhone = true): Json {
  if (typeof value === "string") return scrubString(value, detectPhone);
  if (Array.isArray(value)) return value.map((item) => scrubJson(item, detectPhone));
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, scrubJson(item, detectPhone)]));
  return value;
}
function textParts(value: unknown): string {
  if (!Array.isArray(value)) return "";
  return value.map((item: any) => item?.plain_text ?? item?.text?.content ?? item?.name ?? "").filter(Boolean).join("");
}
function propertyValue(property: any): Json {
  if (!property || typeof property !== "object") return null;
  const type = property.type;
  const value = property[type];
  switch (type) {
    case "title":
    case "rich_text": return textParts(value);
    case "number":
    case "checkbox":
    case "url":
    case "created_time":
    case "last_edited_time": return value ?? null;
    case "select":
    case "status": return value?.name ?? null;
    case "multi_select": return Array.isArray(value) ? value.map((item: any) => item?.name).filter(Boolean) : [];
    case "date": return value ? { start: value.start ?? null, end: value.end ?? null, time_zone: value.time_zone ?? null } : null;
    case "relation": return Array.isArray(value) ? value.map((item: any) => item?.id).filter(Boolean) : [];
    case "files": return Array.isArray(value) ? value.map((item: any) => ({ name: item?.name ?? null, type: item?.type ?? null, url: item?.external?.url ?? item?.file?.url ?? null })).filter((item: any) => item.name) : [];
    case "formula": return propertyValue({ type: value?.type, [value?.type]: value?.[value?.type] });
    case "rollup": {
      if (!value) return null;
      if (value.type === "array") return Array.isArray(value.array) ? value.array.map(propertyValue) : [];
      return propertyValue({ type: value.type, [value.type]: value[value.type] });
    }
    case "unique_id": return value ? `${value.prefix ?? ""}${value.number ?? ""}` : null;
    default: return null;
  }
}
function sanitizeProperties(source: Source, properties: Record<string, any>) {
  const allowed = ALLOWLISTS[source.source_key] ?? new Set<string>();
  const clean: Record<string, Json> = {};
  for (const [name, property] of Object.entries(properties ?? {})) {
    const field = normalize(name);
    if (!allowed.has(field)) continue;
    if (!source.import_pii && ["responsavel", "vendedor", "email", "telefone", "cpf", "rg"].includes(field)) continue;
    const raw = propertyValue(property);
    if (field === "cnpj") clean[name] = digits(scalar(raw)).slice(0, 14);
    else clean[name] = scrubJson(raw, field !== "cnpjclientefilialloja");
  }
  return clean;
}
function valueByAliases(properties: Record<string, Json>, aliases: string[]): any {
  const entries = Object.entries(properties);
  for (const alias of aliases) {
    const wanted = normalize(alias);
    const match = entries.find(([name]) => normalize(name) === wanted);
    if (match) return match[1];
  }
  return null;
}
function scalar(value: any): string {
  if (value == null) return "";
  if (["string", "number", "boolean"].includes(typeof value)) return String(value).trim();
  if (Array.isArray(value)) return value.map(scalar).filter(Boolean).join(", ");
  if (typeof value === "object" && typeof value.start === "string") return value.start;
  return "";
}
function relationIds(value: any): string[] { return Array.isArray(value) ? value.filter((item) => typeof item === "string") : []; }
function pageTitle(page: any, properties: Record<string, Json>) {
  const titleProperty = Object.entries(page.properties ?? {}).find(([, property]: any) => property?.type === "title");
  if (titleProperty && properties[titleProperty[0]] != null) return scalar(properties[titleProperty[0]]);
  return scalar(valueByAliases(properties, ["Nome", "Nº OS", "Descrição Tarefa", "Descrição", "Cliente_Loja", "PATRIMONIO"])) || page.id;
}
function parseDate(value: any): string | null {
  const raw = scalar(value);
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}
function mapTaskStatus(value: any) {
  const status = normalize(scalar(value));
  if (/concluid|feito|finaliz/.test(status)) return "completed";
  if (/andamento|execucao|iniciad/.test(status) && !/naoiniciad/.test(status)) return "in_progress";
  if (/dispens|naoseaplica|cancel/.test(status)) return "waived";
  return "pending";
}
async function must<T extends { error?: any }>(promise: PromiseLike<T>, context: string): Promise<T> {
  const result = await promise;
  if (result.error) throw new Error(`${context}: ${result.error.message ?? result.error}`);
  return result;
}

async function notionRequest(path: string, token: string, init: RequestInit = {}) {
  let lastError = "Falha desconhecida no Notion.";
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetch(`https://api.notion.com${path}`, {
      ...init,
      signal: init.signal ?? AbortSignal.timeout(20_000),
      headers: { Authorization: `Bearer ${token}`, "Notion-Version": NOTION_VERSION, "Content-Type": "application/json", ...(init.headers ?? {}) },
    });
    const payload = await response.json().catch(() => ({}));
    if (response.ok) return payload;
    lastError = `${response.status} ${payload?.code ?? "notion_error"}: ${payload?.message ?? "Falha na API do Notion."}`;
    if (![429, 503, 504, 529].includes(response.status) || attempt === 3) throw new Error(lastError);
    const retryAfter = Number(response.headers.get("retry-after"));
    await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 500 * (2 ** attempt) + Math.floor(Math.random() * 250));
  }
  throw new Error(lastError);
}

async function resolveDataSource(db: any, source: Source, notionToken: string) {
  if (source.data_source_id) return source.data_source_id;
  try {
    const database = await notionRequest(`/v1/databases/${source.database_id}`, notionToken);
    const id = database?.data_sources?.[0]?.id;
    if (id) {
      await must(db.from("notion_sync_sources").update({ data_source_id: id, last_error: null, updated_at: new Date().toISOString() }).eq("id", source.id), "Salvar data_source_id");
      return id as string;
    }
  } catch (error) {
    console.warn("database resolution failed", source.source_key, error instanceof Error ? error.message : error);
  }
  const search = await notionRequest("/v1/search", notionToken, { method: "POST", body: JSON.stringify({ query: source.title, page_size: 20, filter: { property: "object", value: "data_source" } }) });
  const match = (search.results ?? []).find((item: any) => normalize(textParts(item.title)) === normalize(source.title));
  if (!match?.id) throw new Error(`Fonte original não encontrada para ${source.title}. Compartilhe a base original com a integração.`);
  await must(db.from("notion_sync_sources").update({ data_source_id: match.id, last_error: null, updated_at: new Date().toISOString() }).eq("id", source.id), "Salvar data_source_id pesquisado");
  return match.id as string;
}

async function findLink(db: any, pageId: string, entityType: string) {
  const result = await must(db.from("notion_entity_links").select("entity_id,match_strategy").eq("notion_page_id", pageId).eq("entity_type", entityType).limit(1).maybeSingle(), "Buscar vínculo Notion");
  return result.data ?? null;
}
async function saveLink(db: any, sourceId: string, pageId: string, entityType: string, entityId: string, strategy: string) {
  await must(db.from("notion_entity_links").upsert({ source_id: sourceId, notion_page_id: pageId, entity_type: entityType, entity_id: entityId, match_strategy: strategy, updated_at: new Date().toISOString() }, { onConflict: "source_id,notion_page_id,entity_type" }), "Salvar vínculo Notion");
}
async function findClientId(db: any, properties: Record<string, Json>) {
  for (const pageId of relationIds(valueByAliases(properties, ["CNPJ | CLIENTE | FILIAL/LOJA", "Cliente", "Cadastro Cliente"]))) {
    const link = await findLink(db, pageId, "client");
    if (link?.entity_id) return link.entity_id as string;
  }
  const combined = scalar(valueByAliases(properties, ["CNPJ | CLIENTE | FILIAL/LOJA"]));
  const cnpj = digits(combined).slice(0, 14);
  if (cnpj.length === 14) {
    const result = await must(db.from("clients").select("id").eq("cnpj", cnpj).maybeSingle(), "Buscar cliente por CNPJ");
    if (result.data?.id) return result.data.id as string;
  }
  return null;
}

async function materializeClient(db: any, record: Row) {
  const p = record.properties;
  const cnpj = digits(valueByAliases(p, ["CNPJ", "CNPJ | CLIENTE | FILIAL/LOJA"])).slice(0, 14);
  if (cnpj.length !== 14 || record.in_trash) return false;
  const linked = await findLink(db, record.notion_page_id, "client");
  if (linked?.entity_id) {
    await must(db.from("clients").update({ notion_last_edited_at: record.notion_last_edited_at }).eq("id", linked.entity_id).eq("notion_origin", true), "Atualizar metadado do cliente importado");
    return true;
  }
  const existing = await must(db.from("clients").select("id,notion_origin").eq("cnpj", cnpj).maybeSingle(), "Reconciliar cliente por CNPJ");
  if (existing.data?.id) {
    await saveLink(db, record.source_id, record.notion_page_id, "client", existing.data.id, "cnpj");
    return true;
  }
  const legalName = scalar(valueByAliases(p, ["CLIENTE", "Razão Social", "Razao Social"])) || record.title || `Cliente ${cnpj}`;
  const tradeName = scalar(valueByAliases(p, ["FILIAL / LOJA", "FILIAL/LOJA", "Cliente_Loja"])) || null;
  const address = [valueByAliases(p, ["ENDERECO", "Endereço"]), valueByAliases(p, ["CIDADE"]), valueByAliases(p, ["ESTADO"])].map(scalar).filter(Boolean).join(" - ") || null;
  const inserted = await must(db.from("clients").insert({ cnpj, cnpj_raw: cnpj, legal_name: legalName, trade_name: tradeName, address, cnpj_data: { source: "notion", code: scalar(valueByAliases(p, ["CODIGO"])) }, notion_page_id: record.notion_page_id, notion_last_edited_at: record.notion_last_edited_at, notion_origin: true }).select("id").single(), "Criar cliente importado");
  await saveLink(db, record.source_id, record.notion_page_id, "client", inserted.data.id, "created");
  return true;
}

async function ensureImportedPlanning(db: any, projectId: string, record: Row) {
  const existing = await must(db.from("plannings").select("id").eq("project_id", projectId).maybeSingle(), "Verificar planejamento legado");
  if (existing.data?.id) return;
  const p = record.properties;
  const inventoryStart = parseDate(valueByAliases(p, ["Inventario", "Inventário"]));
  const content = {
    store: {
      inventoryStart: inventoryStart?.slice(0, 10) ?? "",
      inventoryStartAt: inventoryStart,
      unit: scalar(valueByAliases(p, ["Cliente_Loja", "FILIAL / LOJA"])),
      headcount: scalar(valueByAliases(p, ["Equipe Total", "T Equipe"])),
    },
    notion: { pageId: record.notion_page_id, url: record.notion_url, lastEditedAt: record.notion_last_edited_at, legacyStatus: scalar(valueByAliases(p, ["Status"])) },
  };
  await must(db.from("plannings").insert({ project_id: projectId, content, status: "in_progress", completion_percentage: 0, notion_page_id: record.notion_page_id }), "Criar planejamento legado");
}

async function materializeOperation(db: any, record: Row) {
  const p = record.properties;
  const originalReference = scalar(valueByAliases(p, ["Nº OS", "Numero OS", "OS"])) || record.title;
  if (!originalReference || record.in_trash) return false;
  const linked = await findLink(db, record.notion_page_id, "project");
  if (linked?.entity_id) {
    const linkedProject = await must(db.from("projects").select("id,notion_origin").eq("id", linked.entity_id).maybeSingle(), "Validar operação vinculada");
    if (linkedProject.data?.id) {
      if (linkedProject.data.notion_origin) {
        await must(db.from("projects").update({ notion_last_edited_at: record.notion_last_edited_at, notion_url: record.notion_url }).eq("id", linked.entity_id), "Atualizar metadado da operação importada");
        await ensureImportedPlanning(db, linked.entity_id, record);
      }
      return true;
    }
    await must(db.from("notion_entity_links").delete().eq("notion_page_id", record.notion_page_id).eq("entity_type", "project"), "Remover vínculo órfão");
  }
  let existing = (await must(db.from("projects").select("id,notion_origin").eq("notion_page_id", record.notion_page_id).limit(1).maybeSingle(), "Reconciliar operação por ID Notion")).data;
  if (!existing?.id) existing = (await must(db.from("projects").select("id,notion_origin").eq("notion_reference", originalReference).limit(1).maybeSingle(), "Reconciliar operação por referência Notion")).data;
  if (!existing?.id) existing = (await must(db.from("projects").select("id,notion_origin").eq("reference", originalReference).limit(1).maybeSingle(), "Reconciliar operação por referência local")).data;
  if (existing?.id) {
    if (existing.notion_origin) await ensureImportedPlanning(db, existing.id, record);
    await saveLink(db, record.source_id, record.notion_page_id, "project", existing.id, existing.notion_origin ? "notion_id" : "reference");
    return true;
  }
  const clientId = await findClientId(db, p);
  const relatedClient = relationIds(valueByAliases(p, ["CNPJ | CLIENTE | FILIAL/LOJA", "Cadastro Cliente"]))[0] ?? null;
  const project = await must(db.from("projects").insert({
    reference: originalReference.slice(0, 120), request_key: record.notion_page_id, client_id: clientId,
    inventory_type: scalar(valueByAliases(p, ["Tipo de Inventario", "Tipo de Inventário"])) || null,
    requires_dimensioning: false, status: "planning", commercial_status: "won",
    operational_notes: `Legado importado do Notion. OS original: ${originalReference}`,
    notion_page_id: record.notion_page_id, notion_reference: originalReference, notion_client_page_id: relatedClient,
    notion_last_edited_at: record.notion_last_edited_at, notion_url: record.notion_url, notion_origin: true,
    requested_at: record.notion_created_at ?? new Date().toISOString(),
  }).select("id").single(), "Criar operação importada");
  await ensureImportedPlanning(db, project.data.id, record);
  await saveLink(db, record.source_id, record.notion_page_id, "project", project.data.id, "created");
  return true;
}

async function materializeTaskTemplate(db: any, record: Row) {
  const p = record.properties;
  const title = scalar(valueByAliases(p, ["Descrição Tarefa", "Tarefa", "Descricao Tarefa"])) || record.title;
  if (!title) return false;
  const code = scalar(valueByAliases(p, ["ID_Tarefa", "ID Tarefa"]));
  const dueRaw = Number(scalar(valueByAliases(p, ["Prazo (Dias)", "PrazoDias"])));
  const orderMatch = code.match(/(\d+)$/);
  const payload = {
    title, description: code ? `Código legado: ${code}` : null,
    inventory_type: scalar(valueByAliases(p, ["Tipo"])) || null,
    due_days_before_inventory: Number.isFinite(dueRaw) && dueRaw >= 0 ? dueRaw : null,
    responsible_role: null,
    active: !record.in_trash, sort_order: orderMatch ? Number(orderMatch[1]) : 0,
    notion_page_id: record.notion_page_id, notion_task_code: code || null,
    notion_last_edited_at: record.notion_last_edited_at, notion_origin: true,
  };
  const existing = await must(db.from("task_templates").select("id,notion_origin").eq("notion_page_id", record.notion_page_id).maybeSingle(), "Buscar modelo importado");
  if (existing.data?.id) {
    if (!existing.data.notion_origin) throw new Error("Conflito de ownership no modelo de tarefa.");
    await must(db.from("task_templates").update(payload).eq("id", existing.data.id), "Atualizar modelo importado");
    await saveLink(db, record.source_id, record.notion_page_id, "task_template", existing.data.id, "notion_id");
    return true;
  }
  if (record.in_trash) return false;
  const inserted = await must(db.from("task_templates").insert(payload).select("id").single(), "Criar modelo importado");
  await saveLink(db, record.source_id, record.notion_page_id, "task_template", inserted.data.id, "created");
  return true;
}

async function materializeProjectTask(db: any, record: Row) {
  const p = record.properties;
  const reference = scalar(valueByAliases(p, ["COD_INV", "Nº OS", "OS"]));
  if (!reference) return false;
  let project = (await must(db.from("projects").select("id").eq("notion_reference", reference).limit(1).maybeSingle(), "Buscar projeto legado")).data;
  if (!project?.id) project = (await must(db.from("projects").select("id").eq("reference", reference).limit(1).maybeSingle(), "Buscar projeto por referência")).data;
  if (!project?.id) throw new Error(`Dependência ausente: operação ${reference}.`);
  const title = scalar(valueByAliases(p, ["Tarefa", "Descrição", "Descricao"])) || record.title;
  if (!title) return false;
  const existing = await must(db.from("project_tasks").select("id,notion_origin,due_overridden,due_at").eq("notion_page_id", record.notion_page_id).maybeSingle(), "Buscar tarefa importada");
  const status = record.in_trash ? "waived" : mapTaskStatus(valueByAliases(p, ["Status"]));
  const payload: Row = {
    project_id: project.id, title,
    description: scalar(valueByAliases(p, ["Descrição", "Descricao"])) || null,
    due_at: parseDate(valueByAliases(p, ["Inicio", "Prazo", "Data Limite"])), status,
    completed_at: status === "completed" ? record.notion_last_edited_at : null,
    notion_page_id: record.notion_page_id, notion_last_edited_at: record.notion_last_edited_at, notion_origin: true,
  };
  if (existing.data?.id) {
    if (!existing.data.notion_origin) throw new Error("Conflito de ownership na tarefa operacional.");
    if (existing.data.due_overridden) delete payload.due_at;
    await must(db.from("project_tasks").update(payload).eq("id", existing.data.id), "Atualizar tarefa importada");
    await saveLink(db, record.source_id, record.notion_page_id, "project_task", existing.data.id, "notion_id");
    return true;
  }
  if (record.in_trash) return false;
  const inserted = await must(db.from("project_tasks").insert(payload).select("id").single(), "Criar tarefa importada");
  await saveLink(db, record.source_id, record.notion_page_id, "project_task", inserted.data.id, "created");
  return true;
}

async function materializeEquipment(db: any, record: Row) {
  const p = record.properties;
  const code = scalar(valueByAliases(p, ["PATRIMONIO", "Patrimônio"])) || record.title;
  const model = scalar(valueByAliases(p, ["MODELO"]));
  const base = scalar(valueByAliases(p, ["FILIAL", "LOCALIZACAO", "LOCALIZAÇÃO"]));
  const name = [code, model].filter(Boolean).join(" · ") || record.title;
  const availableRaw = normalize(scalar(valueByAliases(p, ["Disponivel", "Disponível"])));
  const available = availableRaw ? /sim|true|disponivel/.test(availableRaw) : null;
  const activeRaw = normalize(scalar(valueByAliases(p, ["ATIVO"])));
  const active = !record.in_trash && (activeRaw ? !/nao|false|inativo/.test(activeRaw) : true);
  await must(db.from("notion_resources").upsert({ notion_page_id: record.notion_page_id, resource_type: "collector", code: code || null, name, base: base || null, available, active, metadata: p, notion_url: record.notion_url, notion_last_edited_at: record.notion_last_edited_at, synced_at: new Date().toISOString() }, { onConflict: "notion_page_id" }), "Atualizar recurso importado");
  const existing = await must(db.from("equipment_catalog").select("id,notion_origin").eq("notion_page_id", record.notion_page_id).maybeSingle(), "Buscar equipamento importado");
  const payload = { owner_type: "contagem", name, active, notion_page_id: record.notion_page_id, metadata: p, notion_last_edited_at: record.notion_last_edited_at, notion_origin: true };
  if (existing.data?.id) {
    if (!existing.data.notion_origin) throw new Error("Conflito de ownership no equipamento.");
    await must(db.from("equipment_catalog").update(payload).eq("id", existing.data.id), "Atualizar equipamento importado");
    await saveLink(db, record.source_id, record.notion_page_id, "equipment", existing.data.id, "notion_id");
    return true;
  }
  if (record.in_trash) return false;
  const inserted = await must(db.from("equipment_catalog").insert(payload).select("id").single(), "Criar equipamento importado");
  await saveLink(db, record.source_id, record.notion_page_id, "equipment", inserted.data.id, "created");
  return true;
}

async function materializeDocument(db: any, record: Row, sourceKey: string) {
  const p = record.properties;
  const title = scalar(valueByAliases(p, ["Descrição", "DESCRICAO RESUMIDA", "Descrição resumida"])) || record.title;
  if (!title) return false;
  await must(db.from("notion_documents").upsert({ notion_page_id: record.notion_page_id, source_kind: sourceKey, title, status: record.in_trash ? "removed_in_notion" : scalar(valueByAliases(p, ["Status"])) || null, category: scalar(valueByAliases(p, ["SETOR/AREA", "Tipo", "Categoria"])) || null, document_url: scalar(valueByAliases(p, ["LINK DO DOCUMENTO", "Link", "URL"])) || null, metadata: p, notion_url: record.notion_url, notion_last_edited_at: record.notion_last_edited_at, synced_at: new Date().toISOString() }, { onConflict: "notion_page_id" }), "Atualizar documento importado");
  return true;
}
async function materialize(db: any, source: Source, record: Row) {
  switch (source.target_kind) {
    case "clients": return materializeClient(db, record);
    case "operations": return materializeOperation(db, record);
    case "task_templates": return materializeTaskTemplate(db, record);
    case "project_tasks": return materializeProjectTask(db, record);
    case "equipment": return materializeEquipment(db, record);
    case "documents": return materializeDocument(db, record, source.source_key);
    default: throw new Error(`Materializador não implementado para ${source.target_kind}.`);
  }
}

async function recordFailure(db: any, sourceId: string, pageId: string, error: string) {
  const existing = await must(db.from("notion_materialization_failures").select("attempts").eq("source_id", sourceId).eq("notion_page_id", pageId).maybeSingle(), "Ler dead-letter");
  await must(db.from("notion_materialization_failures").upsert({ source_id: sourceId, notion_page_id: pageId, error: error.slice(0, 2000), attempts: Number(existing.data?.attempts ?? 0) + 1, last_failed_at: new Date().toISOString(), resolved_at: null }, { onConflict: "source_id,notion_page_id" }), "Salvar dead-letter");
}
async function resolveFailure(db: any, sourceId: string, pageId: string) {
  await must(db.from("notion_materialization_failures").update({ resolved_at: new Date().toISOString() }).eq("source_id", sourceId).eq("notion_page_id", pageId).is("resolved_at", null), "Resolver dead-letter");
}
async function checkpoint(db: any, source: Source, payload: Row) {
  const next = source.checkpoint_version + 1;
  const result = await must(db.from("notion_sync_sources").update({ ...payload, checkpoint_version: next }).eq("id", source.id).eq("checkpoint_version", source.checkpoint_version).select("checkpoint_version").maybeSingle(), "Persistir cursor");
  if (!result.data) throw new Error(`Conflito de checkpoint em ${source.source_key}.`);
  source.checkpoint_version = next;
}
async function heartbeatLock(db: any, runId: string) {
  const result = await must(db.from("notion_sync_locks").update({ acquired_at: new Date().toISOString() }).eq("lock_name", "global").eq("run_id", runId).select("run_id").maybeSingle(), "Renovar lock");
  if (!result.data) throw new Error("Lock da sincronização foi perdido.");
}
async function reconcileRemoved(db: any, source: Source, fullStartedAt: string) {
  let total = 0;
  while (true) {
    const stale = await must(db.from("notion_import_records").select("notion_page_id").eq("source_id", source.id).eq("in_trash", false).lt("last_imported_at", fullStartedAt).limit(500), "Listar itens removidos");
    const ids = (stale.data ?? []).map((row: any) => row.notion_page_id);
    if (!ids.length) break;
    await must(db.from("notion_import_records").update({ in_trash: true }).eq("source_id", source.id).in("notion_page_id", ids), "Marcar itens removidos");
    if (source.target_kind === "task_templates") await must(db.from("task_templates").update({ active: false }).eq("notion_origin", true).in("notion_page_id", ids), "Desativar modelos removidos");
    if (source.target_kind === "project_tasks") await must(db.from("project_tasks").update({ status: "waived" }).eq("notion_origin", true).neq("status", "completed").in("notion_page_id", ids), "Dispensar tarefas removidas");
    if (source.target_kind === "equipment") {
      await must(db.from("notion_resources").update({ active: false }).in("notion_page_id", ids), "Desativar recursos removidos");
      await must(db.from("equipment_catalog").update({ active: false }).eq("notion_origin", true).in("notion_page_id", ids), "Desativar equipamentos removidos");
    }
    if (source.target_kind === "documents") await must(db.from("notion_documents").update({ status: "removed_in_notion" }).in("notion_page_id", ids), "Marcar documentos removidos");
    total += ids.length;
  }
  return total;
}

async function syncSource(db: any, source: Source, token: string, input: SyncInput, runId: string) {
  const dataSourceId = await resolveDataSource(db, source, token);
  const pageSize = clamp(input.page_size, 50, 10, 100);
  const maxPages = input.dry_run ? 1 : clamp(input.max_pages_per_source, 10, 1, 50);
  const continuing = Boolean(source.resume_cursor);
  let cursor: string | null = continuing ? source.resume_cursor : null;
  const incremental = continuing ? source.resume_mode === "incremental" : !input.full && Boolean(source.full_sync_completed_at && source.last_successful_sync_at);
  const incrementalSince = incremental ? (continuing && source.resume_since ? source.resume_since : new Date(new Date(source.last_successful_sync_at as string).getTime() - 5 * 60 * 1000).toISOString()) : null;
  const syncStartedAt = continuing && source.resume_started_at ? source.resume_started_at : new Date().toISOString();
  const fullStartedAt = syncStartedAt;
  let pages = 0, seen = 0, upserted = 0, materialized = 0, skipped = 0, reconciled = 0;
  let hasMore = false;
  do {
    if (!input.dry_run) await heartbeatLock(db, runId);
    const body: Row = { page_size: pageSize, sorts: [{ timestamp: "last_edited_time", direction: "ascending" }] };
    if (cursor) body.start_cursor = cursor;
    if (incrementalSince) body.filter = { timestamp: "last_edited_time", last_edited_time: { on_or_after: incrementalSince } };
    const result = await notionRequest(`/v1/data_sources/${dataSourceId}/query`, token, { method: "POST", body: JSON.stringify(body) });
    if (result?.request_status?.type === "incomplete") throw new Error(`Consulta de ${source.title} excedeu o limite do Notion; particionamento temporal é necessário.`);
    const records = (result.results ?? []).filter((page: any) => page?.object === "page").map((page: any) => {
      const properties = sanitizeProperties(source, page.properties ?? {});
      return { source_id: source.id, notion_page_id: page.id, notion_url: canonicalNotionUrl(page.id), title: pageTitle(page, properties), properties, notion_created_at: page.created_time ?? null, notion_last_edited_at: page.last_edited_time ?? null, archived: false, in_trash: Boolean(page.in_trash), last_imported_at: new Date().toISOString(), last_seen_run_id: runId };
    });
    seen += records.length;
    if (!input.dry_run && records.length) {
      await must(db.from("notion_import_records").upsert(records, { onConflict: "source_id,notion_page_id" }), "Persistir espelho sanitizado");
      upserted += records.length;
      const failures: string[] = [];
      for (const record of records) {
        try {
          if (await materialize(db, source, record)) materialized += 1; else skipped += 1;
          await resolveFailure(db, source.id, record.notion_page_id);
        } catch (error) {
          const message = error instanceof Error ? error.message : "Falha desconhecida de materialização.";
          await recordFailure(db, source.id, record.notion_page_id, message);
          failures.push(`${record.notion_page_id}: ${message}`);
        }
      }
      if (failures.length) throw new Error(`${failures.length} registro(s) falharam; cursor preservado. ${failures.slice(0, 3).join(" | ")}`);
    }
    cursor = result.next_cursor ?? null;
    hasMore = Boolean(result.has_more && cursor);
    pages += 1;
    if (!input.dry_run) await checkpoint(db, source, { resume_cursor: hasMore ? cursor : null, resume_mode: hasMore ? (incremental ? "incremental" : "full") : null, resume_since: hasMore ? incrementalSince : null, resume_started_at: hasMore ? syncStartedAt : null, last_attempted_sync_at: new Date().toISOString(), updated_at: new Date().toISOString() });
    if (hasMore) await sleep(350);
  } while (hasMore && pages < maxPages);

  const completedAt = new Date().toISOString();
  if (!input.dry_run) {
    const finishedFull = !incremental && !hasMore;
    if (finishedFull) reconciled = await reconcileRemoved(db, source, fullStartedAt);
    await checkpoint(db, source, { data_source_id: dataSourceId, resume_cursor: hasMore ? cursor : null, resume_mode: hasMore ? (incremental ? "incremental" : "full") : null, resume_since: hasMore ? incrementalSince : null, resume_started_at: hasMore ? syncStartedAt : null, full_sync_completed_at: finishedFull ? completedAt : source.full_sync_completed_at, last_successful_sync_at: hasMore ? source.last_successful_sync_at : syncStartedAt, last_attempted_sync_at: completedAt, last_error: null, updated_at: completedAt });
  }
  return { source_key: source.source_key, data_source_id: dataSourceId, mode: incremental ? "incremental" : "full", pages, seen, upserted, materialized, skipped, reconciled, has_more: hasMore, resume_cursor: hasMore ? cursor : null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return json({ error: "Ambiente Supabase incompleto." }, 500);
  const db = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });
  const presentedHash = await sha256(req.headers.get("x-cron-secret") ?? "");
  const credential = await must(db.from("notion_sync_credentials").select("id").eq("secret_hash", presentedHash).eq("active", true).limit(1).maybeSingle(), "Validar credencial interna");
  if (!credential.data?.id) return json({ error: "Credencial de sincronização inválida." }, 401);
  const notionToken = Deno.env.get("NOTION_TOKEN");
  if (!notionToken) return json({ error: "NOTION_TOKEN não configurado." }, 503);
  let input: SyncInput = {};
  try { input = await req.json(); } catch { input = {}; }
  const triggerKind = input.dry_run ? "dry_run" : "scheduled";
  const run = await must(db.from("notion_sync_runs").insert({ trigger_kind: triggerKind, status: "running" }).select("id").single(), "Criar execução");
  const runId = run.data.id as string;
  await must(db.from("notion_sync_locks").delete().lt("acquired_at", new Date(Date.now() - 5 * 60 * 1000).toISOString()), "Limpar lock expirado");
  const lock = await db.from("notion_sync_locks").insert({ lock_name: "global", run_id: runId });
  if (lock.error) {
    await must(db.from("notion_sync_runs").update({ status: "failed", finished_at: new Date().toISOString(), error: "Outra sincronização está em andamento." }).eq("id", runId), "Finalizar execução concorrente");
    return json({ run_id: runId, error: "Outra sincronização está em andamento." }, 409);
  }
  const heartbeatTimer = setInterval(() => {
    db.from("notion_sync_locks").update({ acquired_at: new Date().toISOString() }).eq("lock_name", "global").eq("run_id", runId).then(({ error }: any) => {
      if (error) console.warn("lock heartbeat failed", error.message);
    });
  }, 60_000);
  try {
    let query = db.from("notion_sync_sources").select("*").eq("enabled", true);
    if (input.source_keys?.length) query = query.in("source_key", input.source_keys.slice(0, 20));
    const sourcesResult = await must(query, "Listar fontes");
    const priorities: Record<string, number> = { clients: 1, operations: 2, task_templates: 3, project_tasks: 4, equipment: 5, documents: 6 };
    const sources = (sourcesResult.data ?? []).sort((a: Source, b: Source) => (priorities[a.target_kind] ?? 99) - (priorities[b.target_kind] ?? 99));
    const results: Row[] = [], failures: Row[] = [];
    for (const source of sources as Source[]) {
      try { results.push(await syncSource(db, source, notionToken, input, runId)); }
      catch (error) {
        const message = error instanceof Error ? error.message : "Falha desconhecida.";
        failures.push({ source_key: source.source_key, error: message });
        if (!input.dry_run) await must(db.from("notion_sync_sources").update({ last_attempted_sync_at: new Date().toISOString(), last_error: message, updated_at: new Date().toISOString() }).eq("id", source.id), "Registrar falha da fonte");
      }
    }
    const totals = results.reduce((acc, item) => ({ seen: acc.seen + Number(item.seen ?? 0), upserted: acc.upserted + Number(item.upserted ?? 0), materialized: acc.materialized + Number(item.materialized ?? 0) }), { seen: 0, upserted: 0, materialized: 0 });
    const status = failures.length === 0 ? "success" : results.length ? "partial" : "failed";
    await must(db.from("notion_sync_runs").update({ status, finished_at: new Date().toISOString(), sources_total: sources.length, sources_succeeded: results.length, sources_failed: failures.length, records_seen: totals.seen, records_upserted: totals.upserted, materialized: totals.materialized, summary: { results, failures }, error: failures.length ? `${failures.length} fonte(s) falharam.` : null }).eq("id", runId), "Finalizar execução");
    return json({ run_id: runId, status, totals, results, failures }, status === "failed" ? 502 : 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha na sincronização.";
    await db.from("notion_sync_runs").update({ status: "failed", finished_at: new Date().toISOString(), error: message }).eq("id", runId);
    return json({ run_id: runId, error: message }, 500);
  } finally {
    clearInterval(heartbeatTimer);
    await db.from("notion_sync_locks").delete().eq("lock_name", "global").eq("run_id", runId);
  }
});
