export const cors = {"access-control-allow-origin":"*","access-control-allow-headers":"authorization, apikey, content-type, x-client-id"};
export function json(status:number, body:unknown) { return new Response(JSON.stringify(body), {status, headers:{...cors,"content-type":"application/json"}}); }
export function error(status:number, code:string, message:string) { return json(status,{error:{code,message}}); }
export async function body(req:Request):Promise<Record<string,unknown>> {
  const length=Number(req.headers.get("content-length") ?? "0");
  if (length > 64_000) throw new Error("request_too_large");
  const value=await req.json(); if (!value || Array.isArray(value) || typeof value!=="object") throw new Error("invalid_json");
  return value as Record<string,unknown>;
}
