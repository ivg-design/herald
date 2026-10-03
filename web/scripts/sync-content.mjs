// Copies the repo's Markdown (README, CHANGELOG, docs/**, clients/README) into web/content so the
// site builds from web/ alone (Vercel root = web). Skips silently when the repo root is not above us.
import { cpSync, existsSync, mkdirSync, readdirSync, statSync, copyFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const web = resolve(here, "..");
const repo = resolve(web, "..");
const out = join(web, "content");

if (!existsSync(join(repo, "docs")) || !existsSync(join(repo, "README.md"))) {
  console.log("sync-content: repo root not found above web/, using committed content/");
  process.exit(0);
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
copyFileSync(join(repo, "README.md"), join(out, "README.md"));
copyFileSync(join(repo, "CHANGELOG.md"), join(out, "CHANGELOG.md"));
mkdirSync(join(out, "clients"), { recursive: true });
copyFileSync(join(repo, "clients", "README.md"), join(out, "clients", "README.md"));

function walk(src, dst) {
  mkdirSync(dst, { recursive: true });
  for (const name of readdirSync(src)) {
    const s = join(src, name);
    if (statSync(s).isDirectory()) {
      if (name === "__pycache__" || name === "assets" || name === "screenshots") continue;
      walk(s, join(dst, name));
    } else if (name.endsWith(".md")) {
      copyFileSync(s, join(dst, name));
    }
  }
}
walk(join(repo, "docs"), join(out, "docs"));
console.log("sync-content: copied README, CHANGELOG, clients and docs into web/content");
