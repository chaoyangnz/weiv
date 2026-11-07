import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveWeivBinaryPath } from "./platform.mjs";
import { canonical, createManagedProject, validateOptions } from "./managed.mjs";

const WEIV_STYLE_SUFFIX = "?weiv-style.css";

function compileWeiv(id, format) {
  const bin = resolveWeivBinaryPath();
  return execFileSync(bin, ["compile", "emit", format, id], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
}

function analyzeWeiv(id) {
  const bin = resolveWeivBinaryPath();
  const output = execFileSync(bin, ["analyze", "component", id, "--json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
  return JSON.parse(output).diagnostics ?? [];
}

export function weiv(options = {}) {
  validateOptions(options);
  const project = createManagedProject(options);
  let config, server, planning = false;
  const values = input => typeof input === "string" ? [input] : Array.isArray(input) ? input : Object.values(input ?? {});
  async function prepare(context, force = false) {
    planning = true;
    try {
      const input = config.build.lib?.entry ?? config.build.rollupOptions.input ?? resolve(config.root, "index.html");
      await project.prepare({ root: config.root, entries: values(input).map(path => resolve(config.root, path)),
        resolveSpecifier: async (id, importer) => {
          const found = await context.resolve(id, importer, { skipSelf: true });
          return found && !found.external && !found.id.startsWith("\0") && existsSync(found.id.split("?")[0]) ? found.id : null;
        },
        onDiagnostics: entries => { for (const entry of entries) context.warn({ message: `[${entry.code}] ${entry.message}`, id: entry.sourcePath,
          ...(entry.location ? { loc: { file: entry.sourcePath, line: entry.location.line, column: Math.max(0, entry.location.column - 1) } } : {}) }); },
      }, force);
      if (server && project.outputRoot && !server.config.server.fs.allow.includes(project.outputRoot)) server.config.server.fs.allow.push(project.outputRoot);
      for (const path of project.watchFiles) context.addWatchFile(path);
    } finally { planning = false; }
  }
  const cellRuntimePath = fileURLToPath(new URL("./runtime/cell.js", import.meta.url));
  const observableRuntimePath = fileURLToPath(new URL("./runtime/observable.js", import.meta.url));
  const routerRuntimePath = fileURLToPath(new URL("./runtime/router.js", import.meta.url));

  return {
    name: "weiv",
    enforce: "pre",
    configResolved(value) { config = value; },
    configureServer(value) {
      server = value;
      const root = canonical(config.root);
      if (!server.config.server.fs.allow.includes(root)) server.config.server.fs.allow.push(root);
    },
    async buildStart() { await prepare(this); },
    closeBundle() { project.dispose(); },
    async handleHotUpdate(context) {
      if (!project.watchFiles.has(canonical(context.file))) return;
      // Vite-specific hot-update hooks do not receive Rollup's plugin context.
      await prepare({
        resolve: (...args) => context.server.pluginContainer.resolveId(...args),
        addWatchFile: path => context.server.watcher.add(path),
        warn: entry => context.server.config.logger.warn(`[weiv] ${entry.id}: ${entry.message}`),
      }, true);
      context.server.moduleGraph.invalidateAll();
      context.server.ws.send({ type: "full-reload", path: "*" });
      return [];
    },
    async resolveId(id, importer) {
      if (id === "weiv:observable" || id === "weiv:router" || id === "weiv:cells") {
        return `\0${id}`;
      }
      if (id.startsWith("/__weiv_packages/")) {
        const origin = importer && project.generated.get(canonical(importer))?.source;
        return this.resolve(id.slice("/__weiv_packages/".length), origin ?? resolve(config.root, "__weiv_entry__.js"), { skipSelf: true });
      }
      if (importer?.split("?")[0].endsWith(".weiv") && id.startsWith(".") && id.endsWith(".mjs")) {
        const source = resolve(dirname(importer.split("?")[0]), `${id.slice(0, -4)}.weiv`);
        if (existsSync(source)) return source;
      }
      if (id.endsWith(WEIV_STYLE_SUFFIX)) {
        const source = id.slice(0, -WEIV_STYLE_SUFFIX.length);
        if (source.startsWith(".") && importer) {
          return `${resolve(dirname(importer.split("?")[0]), source)}${WEIV_STYLE_SUFFIX}`;
        }
        return id;
      }
      if (!planning && project.sources.size && importer) {
        const found = await this.resolve(id, importer, { skipSelf: true });
        if (found && !found.external && existsSync(found.id.split("?")[0])) {
          const record = project.sources.get(canonical(found.id));
          if (record && !record.component) return record.output;
        }
      }
      return null;
    },
    load(id) {
      if (id === "\0weiv:cells") {
        return `export * from ${JSON.stringify(cellRuntimePath)};`;
      }
      if (id === "\0weiv:observable") {
        return `export * from ${JSON.stringify(observableRuntimePath)};`;
      }
      if (id === "\0weiv:router") {
        return `export * from ${JSON.stringify(routerRuntimePath)};`;
      }
      if (id.endsWith(WEIV_STYLE_SUFFIX)) {
        const componentPath = id.slice(0, -WEIV_STYLE_SUFFIX.length);
        this.addWatchFile(componentPath);
        return compileWeiv(componentPath, "css");
      }
      const record = project.generated.get(canonical(id));
      if (record?.component) {
        this.addWatchFile(record.source);
        return `${readFileSync(record.output, "utf8")}\nimport ${JSON.stringify(`${record.source}${WEIV_STYLE_SUFFIX}`)};\n`;
      }
      return null;
    },
    transform(_code, id) {
      if (!id.endsWith(".weiv")) return null;
      for (const diagnostic of analyzeWeiv(id)) {
        if (diagnostic.severity !== "warning") continue;
        const warning = {
          message: `[${diagnostic.code}] ${diagnostic.message}`,
          id
        };
        if (diagnostic.location) {
          warning.loc = {
            file: id,
            line: diagnostic.location.line,
            column: Math.max(0, diagnostic.location.column - 1)
          };
        }
        this.warn(warning);
      }
      return { code: `export * from ${JSON.stringify(project.component(id).output)};\n`, map: null };
    }
  };
}
