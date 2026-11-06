import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";
import { resolveWeivBinaryPath } from "./platform.mjs";
import { canonical, createManagedProject, inside, reactivityMode } from "./managed.mjs";

function compileWeiv(filePath) {
  const bin = resolveWeivBinaryPath();
  const compiled = execFileSync(bin, ["compile", "emit", "js-legacy", filePath], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
  return rewriteRuntimeImports(compiled);
}

function rewriteRuntimeImports(code) {
  return code.replace(
    /import\s*\{([^}]+)\}\s*from\s*["']@weiv\/runtime["'];?/g,
    (_match, importsChunk) => {
      const rawImports = importsChunk
        .split(",")
        .map((entry) => entry.trim())
        .filter(Boolean);

      const routerImports = [];
      const observableImports = [];

      for (const spec of rawImports) {
        const importedName = spec.split(/\s+as\s+/)[0].trim();
        if (importedName === "createRouter") {
          routerImports.push(spec);
        } else {
          observableImports.push(spec);
        }
      }

      const lines = [];
      if (observableImports.length > 0) {
        lines.push(`import { ${observableImports.join(", ")} } from "weiv:observable";`);
      }
      if (routerImports.length > 0) {
        lines.push(`import { ${routerImports.join(", ")} } from "weiv:router";`);
      }
      return lines.join("\n");
    }
  );
}

export function weiv(options = {}) {
  const mode = reactivityMode(options);
  const project = createManagedProject(options);
  const cellRuntimePath = fileURLToPath(new URL("./runtime/cell.js", import.meta.url));
  const observableRuntimePath = fileURLToPath(new URL("./runtime/observable.js", import.meta.url));
  const routerRuntimePath = fileURLToPath(new URL("./runtime/router.js", import.meta.url));

  return {
    name: "weiv",
    setup(build) {
      const entries = build.config.entrypoints.map(entry => path.resolve(typeof entry === "string" ? entry : entry.in));
      let root = options.root ? path.resolve(options.root) : build.config.root ? path.resolve(build.config.root) : process.cwd();
      if (!options.root && !build.config.root && entries.some(entry => !inside(root, entry))) {
        root = path.dirname(entries[0]);
        while (entries.some(entry => !inside(root, entry))) root = path.dirname(root);
      }
      const resolveSource = (specifier, importer) => {
        if (specifier.startsWith("weiv:")) return null;
        const directory = path.dirname(importer);
        const exact = path.isAbsolute(specifier) ? specifier : specifier.startsWith(".") ? path.resolve(directory, specifier) : null;
        if (exact && existsSync(exact)) return canonical(exact);
        try { const resolved = Bun.resolveSync(specifier, directory); return existsSync(resolved) ? canonical(resolved) : null; } catch { return null; }
      };
      build.onStart(async () => {
        if (mode === "managed") await project.prepare({ root, entries, resolveSpecifier: resolveSource,
          onDiagnostics: entries => { for (const entry of entries) console.warn(`[${entry.code}] ${entry.sourcePath}${entry.location ? `:${entry.location.line}:${entry.location.column}` : ""}: ${entry.message}`); },
        }, true);
      });
      // Bun 1.2 exposes an onEnd stub that throws. Dispose on process exit on
      // those versions; newer builders may provide a working disposal hook.
      const cleanup = () => project.dispose();
      try { build.onDispose(cleanup); } catch { process.once("exit", cleanup); }
      build.onResolve({ filter: /^weiv:(observable|router|cells)$/ }, (args) => ({
        path: args.path,
        namespace: "weiv-virtual",
      }));

      build.onLoad({ filter: /^weiv:cells$/, namespace: "weiv-virtual" }, () => ({
        contents: `export * from ${JSON.stringify(cellRuntimePath)};`,
        loader: "js",
      }));

      build.onLoad({ filter: /^weiv:observable$/, namespace: "weiv-virtual" }, () => ({
        contents: `export * from ${JSON.stringify(observableRuntimePath)};`,
        loader: "js",
      }));

      build.onLoad({ filter: /^weiv:router$/, namespace: "weiv-virtual" }, () => ({
        contents: `export * from ${JSON.stringify(routerRuntimePath)};`,
        loader: "js",
      }));

      if (mode === "managed") build.onResolve({ filter: /.*/ }, args => {
        const origin = args.importer && project.generated.get(canonical(args.importer))?.source;
        const importer = origin ?? args.importer ?? path.join(root, "entry.js");
        if (args.path.startsWith("/__weiv_packages/")) {
          const resolved = resolveSource(args.path.slice("/__weiv_packages/".length), importer || path.join(root, "entry.js"));
          if (!resolved) throw new Error(`Cannot resolve managed dependency ${args.path} from ${origin ?? root}`);
          return { path: resolved, namespace: "file" };
        }
        const source = resolveSource(args.path, importer || path.join(root, "entry.js"));
        if (!source) return;
        const record = project.sources.get(source);
        if (record) return { path: record.output, namespace: "file" };
        if (source.endsWith(".weiv")) project.component(source);
      });
      else build.onResolve({ filter: /\.[mc]?js$/ }, args => {
        if (!args.importer?.endsWith(".weiv") || !args.path.startsWith(".")) return;
        const emitted = path.resolve(path.dirname(args.importer), args.path);
        if (existsSync(emitted)) return;
        const candidates = emitted.endsWith(".mjs") ? [`${emitted.slice(0, -4)}.weiv`, `${emitted.slice(0, -4)}.mts`] : [`${emitted.slice(0, -3)}.ts`, `${emitted.slice(0, -3)}.tsx`];
        for (const source of candidates) if (existsSync(source)) return { path: canonical(source), namespace: "file" };
      });

      build.onLoad({ filter: /\.weiv$/ }, (args) => {
        if (mode === "managed") return { contents: `export * from ${JSON.stringify(project.component(args.path).output)};`, loader: "js" };
        const code = compileWeiv(path.resolve(args.path));
        return {
          contents: code,
          loader: "js"
        };
      });
    }
  };
}
