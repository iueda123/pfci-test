// Verifies that every internal document link resolves, including the anchors that
// scripts/doctor.sh prints. A broken anchor turns doctor's guidance into a dead end.
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const markdown = ["README.md", "AGENTS.md", "docs/README.md", "docs/setup-app.md", "docs/setup-env.md", "docs/setup-supabase.md"];
const rootRelative = [".env.example", "supabase/.env.example", "scripts/setup/stages.sh"];

// GitHubのanchor生成にあわせて、記号（ASCII、一般句読点、CJK句読点、全角記号）を落とします。
const punctuation = new RegExp(
  "[\\u0000-\\u001f\\u0021-\\u002c\\u002e-\\u002f\\u003a-\\u0040" +
  "\\u005b-\\u005e\\u0060\\u007b-\\u007e\\u2000-\\u206f\\u3000-\\u303f\\uff01-\\uff20]",
  "g",
);

function slug(text) {
  return text
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/<[^>]*>/g, "")
    .replace(/[`*_~]/g, "")
    .trim()
    .toLowerCase()
    .replace(punctuation, "")
    .replace(/ /g, "-");
}

const anchors = new Map();

function anchorsOf(file) {
  if (anchors.has(file)) return anchors.get(file);
  const found = new Set();
  const counts = new Map();
  let fenced = false;
  for (const line of fs.readFileSync(path.join(root, file), "utf8").split("\n")) {
    if (/^\s*(```|~~~)/.test(line)) { fenced = !fenced; continue; }
    if (fenced) continue;
    const heading = /^(#{1,6})\s+(.*?)\s*$/.exec(line);
    if (!heading) continue;
    const base = slug(heading[2]);
    const seen = counts.get(base) ?? 0;
    counts.set(base, seen + 1);
    found.add(seen === 0 ? base : `${base}-${seen}`);
  }
  anchors.set(file, found);
  return found;
}

const problems = [];

function checkTarget(source, baseDir, target) {
  if (/^(https?:|mailto:)/.test(target)) return;
  let [rawPath, anchor] = target.split("#");
  const file = rawPath
    ? path.relative(root, path.resolve(root, baseDir, rawPath))
    : source;
  if (!fs.existsSync(path.join(root, file))) {
    problems.push(`${source}: file not found -> ${target}`);
    return;
  }
  if (!anchor) return;
  if (!file.endsWith(".md")) {
    problems.push(`${source}: anchor on a non-markdown file -> ${target}`);
    return;
  }
  if (!anchorsOf(file).has(decodeURIComponent(anchor))) {
    problems.push(`${source}: anchor not found -> ${target}`);
  }
}

for (const file of markdown) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  for (const match of text.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
    checkTarget(file, path.dirname(file), match[1]);
  }
}

// doctor.shが案内するdocs参照（.env.exampleの@doc=とstages.shのstage定義）も同じ規則で検査します。
for (const file of rootRelative) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  for (const match of text.matchAll(/(?:@doc=|['"])(docs\/[^\s'"]+)/g)) {
    checkTarget(file, ".", match[1]);
  }
}

if (problems.length) {
  for (const problem of problems) console.error(problem);
  console.error(`Broken document links: ${problems.length}`);
  process.exit(1);
}
console.log("Document links ok");
