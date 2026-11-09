import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, extname, isAbsolute, join, relative, resolve } from "node:path";
import { resolveWeivBinaryPath } from "./platform.mjs";
import { fileURLToPath } from "node:url";

const RUNTIME_FILES = ["binding.js", "cell.js", "index.js", "observable.js", "reactive-core.js", "router.js"];

function runtimeDirectory() {
  const candidates = [
    fileURLToPath(new URL("./runtime", import.meta.url)),
    fileURLToPath(new URL("../dist/runtime", import.meta.url)),
  ];
  const found = candidates.find(directory => RUNTIME_FILES.every(file => existsSync(join(directory, file))));
  // Leave failure reporting to the native CLI so installed-package diagnostics
  // keep one source of truth.
  return found ?? candidates[0];
}

export function validateOptions(options) {
  if (options.reactivity !== undefined) throw new TypeError('The reactivity option has been removed. Use the managed model and await the DOM batch after state writes.');
}

export function canonical(path) {
  const clean = path.split("?")[0];
  return existsSync(clean) ? realpathSync(clean) : resolve(clean);
}

export function inside(root, path) {
  const part = relative(root, path);
  return part === "" || (!part.startsWith("..") && !isAbsolute(part));
}

function diagnostics(stderr) {
  if (!stderr?.trim()) return [];
  try { return JSON.parse(stderr).diagnostics ?? []; } catch { return []; }
}

function run(args) {
  try { return execFileSync(resolveWeivBinaryPath(), args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }); }
  catch (error) {
    const entries = diagnostics(String(error.stderr ?? ""));
    if (!entries.length) throw error;
    throw new Error(entries.map(entry => `[${entry.code}] ${entry.sourcePath}${entry.location ? `:${entry.location.line}:${entry.location.column}` : ""}: ${entry.message}`).join("\n"), { cause: error });
  }
}

// One plan per bundler build. Resolve original consumers and component imports to
// the same emitted module, instead of boxing each component's imports separately.
export function createManagedProject(options = {}) {
  let directory, prepared = false;
  const sources = new Map(), generated = new Map(), watchFiles = new Set();
  return {
    sources, generated, watchFiles,
    get outputRoot() { return directory && join(directory, "output"); },
    async prepare({ root, entries, resolveSpecifier, onDiagnostics }, force = false) {
      if (prepared && !force) return;
      root = canonical(options.root ? resolve(options.root) : root);
      sources.clear();generated.clear();watchFiles.clear();
      const roots = new Set((options.components ?? []).map(path => canonical(resolve(root, path))));
      const visited = new Set();
      const visit = async path => {
        path = canonical(path);
        if (visited.has(path) || !existsSync(path)) return;
        visited.add(path);watchFiles.add(path);
        if (path.endsWith(".weiv")) { roots.add(path); return; }
        if (!inside(root, path) || path.split(/[\\/]/).includes("node_modules")) return;
        const extension = extname(path);
        if (extension !== ".html" && !/\.[cm]?[jt]sx?$/.test(path)) return;
        const source = readFileSync(path, "utf8");
        if (extension === ".html") {
          // HTML only discovers module entry scripts; JavaScript imports use AST facts.
          for (const match of source.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
            if (!/\btype\s*=\s*["']module["']/i.test(match[1])) continue;
            const src = /\bsrc\s*=\s*["']([^"']+)["']/i.exec(match[1]);
            if (src) await visit(src[1].startsWith("/") ? resolve(root, `.${src[1]}`) : resolve(dirname(path), src[1]));
            else if (match[2].trim()) throw new Error("Managed Weiv builds require module entry scripts in files; move this inline module to a script file or supply a file entry.");
          }
          return;
        }
        if (!/\.[cm]?[jt]sx?$/.test(path)) return;
        const facts = JSON.parse(run(["analyze", "module-state", path]));
        if (!facts.ok) return; // Let the bundler report syntax it owns.
        for (const item of facts.sources ?? []) {
          if (item.source.startsWith("weiv:") || item.source.startsWith("node:")) continue;
          const resolved = await resolveSpecifier(item.source, path);
          if (resolved) await visit(resolved);
        }
      };
      for (const entry of entries) await visit(entry);
      for (const component of roots) watchFiles.add(component);
      if (roots.size) {
        directory ??= mkdtempSync(join(tmpdir(), "weiv-managed-"));
        const input = join(directory, "input.json"), output = join(directory, "output");
        writeFileSync(input, JSON.stringify({ root, components: [...roots].sort() }));
        const result = spawnSync(resolveWeivBinaryPath(), ["--runtime-dir", runtimeDirectory(), "--json-diagnostics", "emit", "managed-project", input, output], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
        if (result.error) throw result.error;
        const entries = diagnostics(result.stderr);
        if (result.status !== 0) {
          throw new Error(entries.length ? entries.map(entry => `[${entry.code}] ${entry.sourcePath}${entry.location ? `:${entry.location.line}:${entry.location.column}` : ""}: ${entry.message}`).join("\n") : result.stderr || "Weiv managed build failed");
        }
        const manifest = JSON.parse(readFileSync(join(output, "manifest.json"), "utf8"));
        for (const item of manifest.modules) {
          const emitted = canonical(resolve(output, item.output));
          const record = { ...item, output: emitted };
          sources.set(canonical(item.source), record);generated.set(emitted, record);watchFiles.add(item.source);
        }
        onDiagnostics?.(entries);
      }
      prepared = true;
    },
    component(path) {
      const record = sources.get(canonical(path));
      if (!record?.component) throw new Error(`Weiv component is outside the discovered entry graph: ${path}. Add it to the plugin's components option or include its static import in an entry.`);
      return record;
    },
    dispose() {
      if (directory) rmSync(directory, { recursive: true, force: true });
      directory = undefined;prepared = false;sources.clear();generated.clear();watchFiles.clear();
    },
  };
}
