import {createClient} from "npm:@supabase/supabase-js@2";
export const bucket="user-reports";
export function admin() { return createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}}); }
export function requireDispatcher(req:Request) {
 const expected=Deno.env.get("DISPATCHER_TOKEN");
 const actual=req.headers.get("authorization")??"",wanted=`Bearer ${expected??""}`;let difference=actual.length^wanted.length;for(let i=0;i<Math.max(actual.length,wanted.length);i++)difference|=(actual.charCodeAt(i)||0)^(wanted.charCodeAt(i)||0);
 if (!expected || difference!==0) throw new Error("unauthorized");
}
