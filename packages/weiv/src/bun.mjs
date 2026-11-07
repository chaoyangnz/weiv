import path from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";
import { canonical, createManagedProject, inside, validateOptions } from "./managed.mjs";

export function weiv(options = {}) {
  validateOptions(options);
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
        await project.prepare({ root, entries, resolveSpecifier: resolveSource,
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

      build.onResolve({ filter: /.*/ }, args => {
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
      build.onLoad({ filter: /\.weiv$/ }, (args) => {
        return { contents: `export * from ${JSON.stringify(project.component(args.path).output)};`, loader: "js" };
      });
    }
  };
}
