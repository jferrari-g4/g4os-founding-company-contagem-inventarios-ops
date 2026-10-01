import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info","Access-Control-Allow-Methods":"POST,OPTIONS"};
const response=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const sha256=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))),byte=>byte.toString(16).padStart(2,"0")).join("");
const generateToken=()=>`ctg_${btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll("+","-").replaceAll("/","_").replaceAll("=","")}`;

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
  if(req.method!=="POST")return response({error:"Método não permitido."},405);
  const authorization=req.headers.get("Authorization");
  if(!authorization?.startsWith("Bearer "))return response({error:"Autenticação obrigatória."},401);
  const url=Deno.env.get("SUPABASE_URL")!;const anon=Deno.env.get("SUPABASE_ANON_KEY")!;const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const caller=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
  const {data:{user},error:authError}=await caller.auth.getUser();
  if(authError||!user)return response({error:"Sessão inválida."},401);
  const [{data:roles,error:roleError},{data:profile,error:profileError}]=await Promise.all([caller.from("user_roles").select("role").eq("user_id",user.id).limit(20),caller.from("profiles").select("active").eq("id",user.id).maybeSingle()]);
  if(roleError||profileError||!profile?.active||!roles?.length)return response({error:"Seu usuário não possui perfil operacional ativo."},403);
  const admin=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
  let input:{action?:string;connectionId?:string;label?:string;scopes?:string[]}={};try{input=await req.json()}catch{return response({error:"JSON inválido."},400)}
  const endpoint=`${url}/functions/v1/contagem-ops-mcp`;
  const columns="id,owner_user_id,label,token_prefix,scopes,active,created_at,last_used_at,revoked_at";
  if(input.action==="list"){
    const [connections,events]=await Promise.all([admin.from("contagem_g4os_connections").select(columns).eq("owner_user_id",user.id).order("created_at",{ascending:false}),admin.from("contagem_g4os_events").select("id,occurred_at,tool_name,operation,success,duration_ms,details").eq("actor_user_id",user.id).order("occurred_at",{ascending:false}).limit(20)]);
    if(connections.error||events.error)return response({error:"Não foi possível carregar as conexões."},500);
    return response({endpoint,connections:connections.data??[],events:events.data??[]});
  }
  if(input.action==="create"||input.action==="rotate"){
    const requestedScopes=Array.isArray(input.scopes)?[...new Set(input.scopes.map(String))]:["read","write"];
    if(!requestedScopes.length||requestedScopes.some(scope=>!["read","write"].includes(scope)))return response({error:"Escopos inválidos."},400);
    const token=generateToken();const token_hash=await sha256(token);const prefix=`${token.slice(0,12)}…`;
    const {data,error:rotateError}=await admin.rpc("g4os_rotate_connection",{p_owner_user_id:user.id,p_label:input.label?.trim().slice(0,80)||"G4 OS",p_token_hash:token_hash,p_token_prefix:prefix,p_scopes:requestedScopes,p_rotate:input.action==="rotate"});
    if(rotateError)return response({error:rotateError.message.includes("Já existe")?"Já existe uma conexão ativa. Rotacione ou revogue a credencial atual.":"Não foi possível criar a conexão."},rotateError.message.includes("Já existe")?409:500);
    await admin.from("contagem_g4os_events").insert({connection_id:data.id,actor_user_id:user.id,tool_name:"connection.created",operation:"AUTH",success:true,details:{rotated:input.action==="rotate",scopes:requestedScopes}});
    return response({endpoint,connection:data,token,warning:"Copie agora. Por segurança, este token não será exibido novamente."},201);
  }
  if(input.action==="revoke"){
    if(!input.connectionId)return response({error:"Conexão obrigatória."},400);
    const {data,error}=await admin.from("contagem_g4os_connections").update({active:false,revoked_at:new Date().toISOString()}).eq("id",input.connectionId).eq("owner_user_id",user.id).eq("active",true).select("id").maybeSingle();
    if(error)return response({error:"Não foi possível revogar a conexão."},500);if(!data)return response({error:"Conexão ativa não encontrada."},404);
    await admin.from("contagem_g4os_events").insert({connection_id:data.id,actor_user_id:user.id,tool_name:"connection.revoked",operation:"AUTH",success:true,details:{}});return response({revoked:true});
  }
  return response({error:"Ação inválida."},400);
});
