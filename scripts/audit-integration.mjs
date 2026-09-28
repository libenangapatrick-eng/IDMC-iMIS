import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";
import process from "node:process";

const root = resolve(import.meta.dirname, "..");
const writeMode = process.argv.includes("--write");
const failures = [];
const walk = directory => readdirSync(directory, { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? walk(join(directory, entry.name)) : [join(directory, entry.name)]);
const text = file => readFileSync(file, "utf8").replace(/^\uFEFF/, "");
const hash = value => createHash("sha256").update(value).digest("hex");
const save = (path, value) => { if (!writeMode) return; const target = join(root, path); mkdirSync(dirname(target), { recursive: true }); writeFileSync(target, value); };

const migrationDir = join(root, "supabase/migrations");
const migrations = walk(migrationDir).filter(file => extname(file) === ".sql").sort().map(file => {
  const name = file.split(/[\\/]/).pop(); const source = text(file); const version = name.split("_")[0];
  return { version, name, sha256: hash(source), bytes: Buffer.byteLength(source), transactional: /^\s*BEGIN;/i.test(source) && /COMMIT;\s*$/i.test(source), source_of_truth: true };
});
const versionGroups = new Map();
for (const item of migrations) versionGroups.set(item.version, [...(versionGroups.get(item.version) ?? []), item]);
for (const [version, items] of versionGroups) if (items.length > 1) failures.push(`Duplicate migration version ${version}: ${items.map(x => x.name).join(", ")}`);
save("supabase/migration-manifest.json", JSON.stringify({ generated_at: new Date().toISOString(), authoritative_directory: "supabase/migrations", reference_only_directory: "database/migrations", migrations }, null, 2) + "\n");

const routeFiles = walk(join(root, "apps/backend/src")).filter(file => file.endsWith(".routes.ts") || file.endsWith("/routes/index.ts"));
const routeRows = [];
for (const file of routeFiles) {
  const source = text(file); const fileName = relative(root, file).replaceAll("\\", "/");
  for (const match of source.matchAll(/router\.(get|post|put|patch|delete|use)\(\s*["'`]([^"'`]+)["'`]/g)) routeRows.push({ method: match[1].toUpperCase(), path: match[2], source: fileName });
  for (const match of source.matchAll(/registerCrudResource\([\s\S]*?permissionView:\s*["']([^"']+)["'][\s\S]*?permissionManage:\s*["']([^"']+)["'][\s\S]*?,\s*["']([^"']+)["']\s*\);/g)) {
    for (const method of ["GET", "GET/:id", "POST", "PATCH/:id", "DELETE/:id"]) routeRows.push({ method, path: match[3], source: fileName, permissions: `${match[1]} | ${match[2]}` });
  }
}
routeRows.sort((a,b) => a.source.localeCompare(b.source) || a.path.localeCompare(b.path) || a.method.localeCompare(b.method));
save("docs/api/generated-route-inventory.json", JSON.stringify({ generated_at: new Date().toISOString(), count: routeRows.length, routes: routeRows }, null, 2) + "\n");
save("docs/api/generated-route-inventory.md", `# Generated Route Inventory\n\nGenerated from backend route source. Mount prefixes remain documented in \`apps/backend/src/routes/index.ts\` and \`app.ts\`.\n\n| Method | Local path | Permissions | Source |\n|---|---|---|---|\n${routeRows.map(x => `| ${x.method} | \`${x.path}\` | ${x.permissions || "See route middleware"} | \`${x.source}\` |`).join("\n")}\n`);

const htmlFiles = walk(join(root, "apps/frontend")).filter(file => file.endsWith(".html"));
const forms = [];
for (const file of htmlFiles) {
  const source = text(file); const page = relative(join(root, "apps/frontend"), file).replaceAll("\\", "/");
  for (const match of source.matchAll(/<form\b([^>]*)>([\s\S]*?)<\/form>/gi)) {
    const attrs = match[1], body = match[2];
    const attr = name => attrs.match(new RegExp(`${name}=["']([^"']+)["']`, "i"))?.[1] ?? null;
    const fields = [...body.matchAll(/<(?:input|select|textarea)\b[^>]*\bname=["']([^"']+)["']/gi)].map(x => x[1]);
    forms.push({ page, form_id: attr("id"), method: (attr("method") || "JS").toUpperCase(), action: attr("action"), fields: [...new Set(fields)] });
  }
}
save("docs/api/generated-form-inventory.json", JSON.stringify({ generated_at: new Date().toISOString(), count: forms.length, forms }, null, 2) + "\n");
save("docs/api/generated-form-inventory.md", `# Generated Form Inventory\n\nThis is structural discovery. The E2E status remains unverified until a real browser session confirms persistence.\n\n| Page | Form ID | Submit | Fields |\n|---|---|---|---|\n${forms.map(x => `| \`${x.page}\` | ${x.form_id ? `\`${x.form_id}\`` : "(none)"} | ${x.action || x.method} | ${x.fields.map(f => `\`${f}\``).join(", ")} |`).join("\n")}\n`);

const frontendScripts = walk(join(root, "apps/frontend/assets/js")).filter(file => file.endsWith(".js"));
for (const file of frontendScripts) {
  const source = text(file);
  if (/API_BASE_URL\s*:\s*["']http:\/\/(?:127\.|localhost)/i.test(source)) failures.push(`Hard-coded loopback API base in ${relative(root,file)}`);
  if (/SUPABASE_SERVICE_ROLE_KEY\s*[:=]/i.test(source)) failures.push(`Potential service-role material in frontend source ${relative(root,file)}`);
}
if (!existsSync(join(root, ".gitignore")) || !/\.env/.test(text(join(root, ".gitignore")))) failures.push(".gitignore does not protect .env files");

const summary = { migrations: migrations.length, routes: routeRows.length, forms: forms.length, failures };
console.log(JSON.stringify(summary, null, 2));
if (failures.length) process.exitCode = 1;
