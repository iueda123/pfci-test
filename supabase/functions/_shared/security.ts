const SECRET=/(?:bearer\s+[a-z0-9._-]+|gh[opsu]_[a-z0-9]{20,}|eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+|https?:\/\/[^\s:@]+:[^\s@]+@)/gi;
const EMAIL=/[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}/gi;
const SESSION=/(?:session[_-]?id|jsessionid)\s*[:=]\s*[^\s,;]+/gi;
const CONNECTION=/\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s]+/gi;
export function sanitize(value:unknown,max=4000):string {
 return String(value ?? "").replace(/[\r\n]+/g," ").replace(/[<>\u0000-\u001f]/g,"").replace(SECRET,"[REDACTED:SECRET]").replace(EMAIL,"[REDACTED:EMAIL]").replaceAll("@","＠").trim().slice(0,max);
}
export function assertSafeIssue(text:string) {
 if (containsSensitive(text) || /https?:\/\/[^\s]*token=/i.test(text) || /reports\/[^\s]+\/raw\//i.test(text)) throw new Error("unsafe_issue_body");
}
export function containsSensitive(text:string):boolean { for(const pattern of [SECRET,EMAIL,SESSION,CONNECTION])pattern.lastIndex=0;return SECRET.test(text)||EMAIL.test(text)||SESSION.test(text)||CONNECTION.test(text); }
export function artifactPath(reportId:string,kind:string):string {
 const paths:Record<string,string>={rawScreenshot:"raw/screenshot.png",rawLog:"raw/logs.jsonl",redactedScreenshot:"redacted/screenshot.png",redactedLog:"redacted/logs.jsonl",manifest:"manifest.json"};
 if (!paths[kind]) throw new Error("invalid_artifact_kind"); return `reports/${reportId}/${paths[kind]}`;
}
