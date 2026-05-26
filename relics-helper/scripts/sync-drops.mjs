import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const URL =
  "https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(root, "public", "drops.html");

const response = await fetch(URL);
if (!response.ok) throw new Error(`HTTP ${response.status}`);
const html = await response.text();
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
console.log(`Wrote ${(html.length / 1024 / 1024).toFixed(2)} MB -> ${out}`);
