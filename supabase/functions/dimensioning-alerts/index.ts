import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const sha256=async(value:string)=>{const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));return [...new Uint8Array(d)].map(b=>b.toString(16).padStart(2,"0")).join("");};
Deno.serve(async(req)=>{
  if(req.method!=="GET"&&req.method!=="POST")return json({error:"Use GET ou POST."},405);
  const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"")||"";
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return json({error:"Ambiente incompleto."},500);
  const db=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const credential=await db.from("internal_api_credentials").select("name").eq("name","dimensioning-alerts").eq("secret_hash",await sha256(token)).eq("active",true).maybeSingle();
  if(credential.error||!credential.data)return json({error:"Não autorizado."},401);
  const cutoff=new Date(Date.now()-864e5).toISOString();
  const result=await db.from("projects").select("id,reference,created_at,client:clients(legal_name)").eq("status","awaiting_dimensioning").lt("created_at",cutoff);
  if(result.error)return json({error:result.error.message},500);
  return json({alerts:result.data||[],count:(result.data||[]).length,cutoff});
});
