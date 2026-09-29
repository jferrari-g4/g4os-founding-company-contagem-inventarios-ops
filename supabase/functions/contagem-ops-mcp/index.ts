import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Obj=Record<string,unknown>; type Rpc={id?:string|number|null;method?:string;params?:{name?:string;arguments?:Obj}};
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,content-type,mcp-protocol-version,mcp-session-id","Access-Control-Allow-Methods":"POST,OPTIONS"};
const header={...cors,"Content-Type":"application/json"};
const sha256=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))),byte=>byte.toString(16).padStart(2,"0")).join("");
const out=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:header});
const result=(id:Rpc["id"],value:unknown)=>out({jsonrpc:"2.0",id:id??null,result:value});
const fail=(id:Rpc["id"],message:string,code=-32000)=>out({jsonrpc:"2.0",id:id??null,error:{code,message}});
const tool=(value:unknown)=>({content:[{type:"text",text:JSON.stringify(value,null,2)}],structuredContent:value});
const error=(message:string)=>({content:[{type:"text",text:message}],isError:true});
const bounded=(value:unknown,fallback=25)=>Math.max(1,Math.min(100,Number(value)||fallback));
const operational=new Set(["admin","operational","operational_supervisor","operational_manager","coordinator"]);
const planningEditors=new Set(["admin","commercial","operational_supervisor","operational_manager"]);
const tools=[
  ["contagem_overview","Resumo operacional e permissões da conexão.",{}],
  ["contagem_list_projects","Lista operações por etapa com paginação.",{status:{type:"string"},search:{type:"string",maxLength:120},limit:{type:"integer",minimum:1,maximum:100},offset:{type:"integer",minimum:0,maximum:10000}}],
  ["contagem_get_project","Detalhe consolidado de uma operação, com dimensionamento, TI, planejamento e tarefas.",{project_id:{type:"string"}}],
  ["contagem_list_tasks","Lista tarefas operacionais por status, operação ou responsável.",{project_id:{type:"string"},status:{type:"string"},search:{type:"string",maxLength:120},limit:{type:"integer",minimum:1,maximum:100}}],
  ["contagem_list_calendar","Lista operações com início de inventário em um intervalo de datas.",{start_date:{type:"string"},end_date:{type:"string"}}],
  ["contagem_update_task","Atualiza responsável, prazo ou status de tarefa. Restrito a perfis operacionais.",{task_id:{type:"string"},status:{type:"string",enum:["pending","in_progress","completed","waived"]},responsible_name:{type:"string",maxLength:160},due_at:{type:"string"}}],
  ["contagem_create_request","Cria solicitação idempotente. Restrito a Comercial e gestores.",{idempotency_key:{type:"string",description:"UUID gerado pelo cliente"},cnpj:{type:"string"},legal_name:{type:"string"},contact_name:{type:"string"},contact_email:{type:"string"},inventory_type:{type:"string"},requires_dimensioning:{type:"boolean"}}]
].map(([name,description,properties])=>({name,title:String(name).replaceAll("_"," "),description,inputSchema:{type:"object",properties,additionalProperties:false},annotations:{readOnlyHint:!String(name).includes("update")&&!String(name).includes("create"),destructiveHint:false,idempotentHint:true,openWorldHint:false}}));

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});if(req.method!=="POST")return out({error:"Use POST."},405);
  const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");if(!token)return out({error:"Bearer obrigatório."},401);
  const url=Deno.env.get("SUPABASE_URL")!;const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const db=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:connection}=await db.from("contagem_g4os_connections").select("id,owner_user_id,scopes").eq("token_hash",await sha256(token)).eq("active",true).maybeSingle();
  if(!connection)return out({error:"Credencial inválida ou revogada."},401);
  const {data:roles}=await db.from("user_roles").select("role").eq("user_id",connection.owner_user_id);const roleList=(roles??[]).map(row=>String(row.role));
  let rpc:Rpc;try{rpc=await req.json()}catch{return fail(null,"JSON-RPC inválido",-32700)}
  if(rpc.method==="initialize")return result(rpc.id,{protocolVersion:"2025-06-18",capabilities:{tools:{}},serverInfo:{name:"contagem-ops-mcp",version:"1.0.0"}});
  if(rpc.method==="notifications/initialized")return new Response(null,{status:202,headers:cors});
  if(rpc.method==="tools/list")return result(rpc.id,{tools});
  if(rpc.method!=="tools/call")return fail(rpc.id,"Método não suportado",-32601);
  const name=rpc.params?.name||"";const args=rpc.params?.arguments||{};const started=Date.now();let operation="READ";
  const audit=async(success:boolean,details:Obj={})=>{await db.from("contagem_g4os_events").insert({connection_id:connection.id,actor_user_id:connection.owner_user_id,tool_name:name,operation,success,duration_ms:Date.now()-started,details})};
  try{
    if(name==="contagem_overview"){
      const statuses=["received","awaiting_dimensioning","awaiting_ti","planning","confirmed"];const counts=Object.fromEntries(await Promise.all(statuses.map(async status=>[status,(await db.from("projects").select("id",{count:"exact",head:true}).eq("status",status).is("deleted_at",null)).count??0])));const payload={roles:roleList,scopes:connection.scopes,projects:counts};await audit(true);return result(rpc.id,tool(payload));
    }
    if(name==="contagem_list_projects"){
      let query=db.from("projects").select("id,reference,status,inventory_type,requires_dimensioning,created_at,clients(legal_name,trade_name,cnpj),plannings(content,status)",{count:"exact"}).is("deleted_at",null).order("created_at",{ascending:false}).range(Number(args.offset)||0,(Number(args.offset)||0)+bounded(args.limit)-1);if(args.status)query=query.eq("status",String(args.status));const {data,count,error:queryError}=await query;if(queryError)throw queryError;const search=String(args.search||"").trim().toLocaleLowerCase("pt-BR");const items=(data??[]).filter((item:any)=>!search||[item.reference,item.inventory_type,item.clients?.legal_name,item.clients?.trade_name,item.clients?.cnpj].some(value=>String(value||"").toLocaleLowerCase("pt-BR").includes(search))).map((item:any)=>({id:item.id,reference:item.reference,status:item.status,inventory_type:item.inventory_type,requires_dimensioning:item.requires_dimensioning,created_at:item.created_at,company:item.clients?.legal_name,trade_name:item.clients?.trade_name,cnpj:item.clients?.cnpj,inventory_start:item.plannings?.content?.store?.inventoryStart||null}));await audit(true,{returned:items.length});return result(rpc.id,tool({items,total:count??items.length}));
    }
    if(name==="contagem_get_project"){
      const projectId=String(args.project_id||"");if(!projectId)throw new Error("project_id obrigatório.");const {data,error:queryError}=await db.from("projects").select("*,clients(*),dimensionings(*),dimensioning_options(*),date_options(*),ti_validations(*),plannings(*),project_tasks(*)").eq("id",projectId).maybeSingle();if(queryError||!data)throw new Error("Operação não encontrada.");await audit(true);return result(rpc.id,tool(data));
    }
    if(name==="contagem_list_tasks"){
      let query=db.from("project_tasks").select("id,project_id,title,description,responsible_role,responsible_name,due_at,status,completed_at,projects(reference,status,clients(legal_name))").order("due_at",{ascending:true,nullsFirst:false}).limit(bounded(args.limit));if(args.project_id)query=query.eq("project_id",String(args.project_id));if(args.status)query=query.eq("status",String(args.status));const {data,error:queryError}=await query;if(queryError)throw queryError;const search=String(args.search||"").toLocaleLowerCase("pt-BR");const items=(data??[]).filter((row:any)=>!search||[row.title,row.responsible_name,row.responsible_role,row.projects?.reference,row.projects?.clients?.legal_name].some(value=>String(value||"").toLocaleLowerCase("pt-BR").includes(search)));await audit(true,{returned:items.length});return result(rpc.id,tool({items}));
    }
    if(name==="contagem_list_calendar"){
      const {data,error:queryError}=await db.from("plannings").select("project_id,content,status,projects(reference,status,clients(legal_name))").limit(500);if(queryError)throw queryError;const start=String(args.start_date||"");const end=String(args.end_date||"");const items=(data??[]).filter((row:any)=>{const date=row.content?.store?.inventoryStart||"";return date&&(!start||date>=start)&&(!end||date<=end)}).map((row:any)=>({project_id:row.project_id,reference:row.projects?.reference,company:row.projects?.clients?.legal_name,status:row.projects?.status,inventory_start:row.content?.store?.inventoryStart,inventory_end:row.content?.store?.inventoryEnd,headcount:row.content?.store?.headcount}));await audit(true,{returned:items.length});return result(rpc.id,tool({items}));
    }
    operation="WRITE";
    if(name==="contagem_update_task"){
      if(!roleList.some(role=>operational.has(role)))throw new Error("Seu perfil não pode alterar tarefas operacionais.");const taskId=String(args.task_id||"");if(!taskId)throw new Error("task_id obrigatório.");const patch:Obj={updated_at:new Date().toISOString()};if(args.status){patch.status=args.status;if(args.status==="completed"){patch.completed_at=new Date().toISOString();patch.completed_by=connection.owner_user_id}else {patch.completed_at=null;patch.completed_by=null}}if(args.responsible_name!==undefined)patch.responsible_name=String(args.responsible_name).slice(0,160);if(args.due_at!==undefined){patch.due_at=args.due_at||null;patch.due_overridden=true}const {data,error:writeError}=await db.from("project_tasks").update(patch).eq("id",taskId).select().single();if(writeError)throw writeError;await audit(true,{task_id:taskId});return result(rpc.id,tool(data));
    }
    if(name==="contagem_create_request"){
      if(!roleList.some(role=>planningEditors.has(role)))throw new Error("Seu perfil não pode criar solicitações.");const key=String(args.idempotency_key||"");if(!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(key))throw new Error("idempotency_key deve ser um UUID.");const {data,error:writeError}=await db.rpc("g4os_create_project_request",{p_actor_id:connection.owner_user_id,p_request_key:key,p_cnpj:String(args.cnpj||"").replace(/\D/g,""),p_cnpj_raw:String(args.cnpj||""),p_legal_name:String(args.legal_name||""),p_trade_name:null,p_address:null,p_contact_name:String(args.contact_name||""),p_contact_email:String(args.contact_email||""),p_contact_phone:null,p_inventory_type:String(args.inventory_type||"")||null,p_layout_system:null,p_ti_contact_name:null,p_ti_contact_email:null,p_ti_contact_phone:null,p_requires_dimensioning:args.requires_dimensioning!==false,p_operational_notes:"Criada pelo G4 OS",p_field_values:[],p_planning_content:null});if(writeError)throw writeError;await audit(true,{project_id:data});return result(rpc.id,tool({project_id:data}));
    }
    throw new Error("Ferramenta não encontrada.");
  }catch(cause){const message=cause instanceof Error?cause.message:"Falha ao executar ferramenta.";await audit(false,{message});return result(rpc.id,error(message));}
});
