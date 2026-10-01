import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-supabase-api-version","Access-Control-Allow-Methods":"POST,OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const rolesAllowed=new Set(["admin","commercial","operational_supervisor","operational_manager","operational","ti","coordinator","viewer"]);

Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
  if(req.method!=="POST")return json({error:"Use POST."},405);
  const bearer=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");
  if(!bearer)return json({error:"Sessão obrigatória."},401);
  const url=Deno.env.get("SUPABASE_URL");const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return json({error:"Ambiente incompleto."},500);
  const db=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:{user},error:userError}=await db.auth.getUser(bearer);
  if(userError||!user)return json({error:"Sessão inválida."},401);
  const [{data:adminRole},{data:profile}]=await Promise.all([db.from("user_roles").select("role").eq("user_id",user.id).eq("role","admin").maybeSingle(),db.from("profiles").select("active").eq("id",user.id).maybeSingle()]);
  if(!profile?.active||!adminRole)return json({error:"Somente administradores ativos."},403);
  let body:any={};try{body=await req.json()}catch{return json({error:"JSON inválido."},400)}
  const action=String(body.action||"");
  try{
    if(action==="list_users"){
      const [{data:profiles,error:pe},{data:roles,error:re}]=await Promise.all([db.from("profiles").select("id,full_name,email,active,created_at,updated_at").order("full_name"),db.from("user_roles").select("user_id,role")]);
      if(pe)throw pe;if(re)throw re;
      return json({users:(profiles||[]).map(profile=>({...profile,roles:(roles||[]).filter(item=>item.user_id===profile.id).map(item=>item.role)}))});
    }
    if(action==="invite_user"){
      const email=String(body.email||"").trim().toLowerCase();const fullName=String(body.full_name||"").trim();const roleList=Array.isArray(body.roles)?body.roles.map(String):["viewer"];
      if(!/^\S+@\S+\.\S+$/.test(email))throw new Error("E-mail inválido.");if(!roleList.length||roleList.some(role=>!rolesAllowed.has(role)))throw new Error("Informe ao menos um papel válido.");
      const {data,error}=await db.auth.admin.inviteUserByEmail(email,{data:{full_name:fullName||email}});if(error)throw error;const invited=data.user;if(!invited)throw new Error("Convite não criado.");
      try{const profileResult=await db.from("profiles").upsert({id:invited.id,full_name:fullName||email,email,active:true},{onConflict:"id"});if(profileResult.error)throw profileResult.error;
      await db.from("user_roles").delete().eq("user_id",invited.id);
      const {error:roleError}=await db.from("user_roles").insert(roleList.map(role=>({user_id:invited.id,role})));if(roleError)throw roleError;
      await db.from("audit_logs").insert({entity:"profiles",entity_id:invited.id,action:"user_invited",after_data:{email,roles:roleList},actor_id:user.id});
      return json({user:{id:invited.id,email,full_name:fullName||email,active:true,roles:roleList}});}catch(setupError){await db.auth.admin.deleteUser(invited.id);throw setupError;}
    }
    if(action==="update_user"){
      const userId=String(body.user_id||"");const roleList=Array.isArray(body.roles)?body.roles.map(String):[];
      if(!userId)throw new Error("user_id obrigatório.");if(roleList.some(role=>!rolesAllowed.has(role)))throw new Error("Papel inválido.");
      const {data,error}=await db.rpc("g4os_set_user_access",{p_actor_id:user.id,p_user_id:userId,p_full_name:body.full_name??null,p_active:body.active??true,p_roles:roleList});if(error)throw error;
      return json({user:data});
    }
    if(action==="save_field"){
      const item=body.item||{};const {data,error}=await db.rpc("g4os_upsert_custom_field_v2",{p_actor_id:user.id,p_field_id:item.id||null,p_field_key:item.field_key||null,p_label:item.label||"",p_field_type:item.field_type||"text",p_required:item.required??false,p_active:item.active??true,p_stage:item.stage||"request",p_show_when_dimensioning:item.show_when_dimensioning??false,p_sort_order:item.sort_order??0,p_options:Array.isArray(item.options)?item.options:[],p_placeholder:item.placeholder||null,p_help_text:item.help_text||null});if(error)throw error;return json({id:data});
    }
    if(action==="delete_field"){
      const {error}=await db.rpc("g4os_delete_custom_field",{p_actor_id:user.id,p_field_id:body.field_id});if(error)throw error;return json({deleted:true});
    }
    if(action==="save_task_template"){
      const item=body.item||{};const {data,error}=await db.rpc("g4os_upsert_task_template",{p_actor_id:user.id,p_template_id:item.id||null,p_title:item.title||"",p_description:item.description||null,p_inventory_type:item.inventory_type||null,p_due_days_before_inventory:item.due_days_before_inventory??null,p_responsible_role:item.responsible_role||null,p_active:item.active??true,p_sort_order:item.sort_order??0});if(error)throw error;return json({id:data});
    }
    if(action==="save_catalog"){
      const {data,error}=await db.rpc("g4os_upsert_admin_catalog",{p_actor_id:user.id,p_catalog:body.catalog,p_item:body.item||{}});if(error)throw error;return json({item:data});
    }
    if(action==="save_checklist"){
      const item=body.item||{};const {data,error}=await db.rpc("g4os_upsert_checklist_template",{p_actor_id:user.id,p_template_id:item.id||null,p_name:item.name||"",p_checklist_type:item.checklist_type||"planning",p_inventory_type:item.inventory_type||null,p_active:item.active??true,p_items:Array.isArray(item.items)?item.items:[]});if(error)throw error;return json({item:data});
    }
    if(action==="manage_lifecycle"){
      const {data,error}=await db.rpc("g4os_manage_project_lifecycle",{p_actor_id:user.id,p_project_id:body.project_id,p_action:body.lifecycle_action,p_reason:body.reason||null,p_stage_key:body.stage_key||null});if(error)throw error;return json({project:data});
    }
    if(action==="save_project_core"){
      const {data,error}=await db.rpc("g4os_update_project_core",{p_actor_id:user.id,p_project_id:body.project_id,p_expected_updated_at:body.expected_updated_at||null,p_project:body.project||{},p_client:body.client||{},p_contact:body.contact||{},p_field_values:Array.isArray(body.field_values)?body.field_values:[]});if(error)throw error;return json({project:data});
    }
    throw new Error("Ação não suportada.");
  }catch(error){return json({error:error instanceof Error?error.message:"Falha administrativa."},400)}
});
