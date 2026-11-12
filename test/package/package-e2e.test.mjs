import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function run(cmd, args, cwd, env = process.env) {
  execFileSync(cmd, args, {
    cwd,
    env,
    stdio: "inherit",
  });
}

function assertExists(path) {
  if (!existsSync(path)) {
    throw new Error(`Expected file to exist: ${path}`);
  }
}

const packageSpec = process.env.WEIVJS_PACKAGE_SPEC ?? "weivjs";
const registry = process.env.NPM_REGISTRY_URL ?? "https://registry.npmjs.org/";
const keepTemp = process.env.WEIVJS_PKG_E2E_KEEP === "1";
const tmpRoot = mkdtempSync(join(tmpdir(), "weivjs-pkg-e2e-"));

try {
  run("npm", ["init", "-y"], tmpRoot);
  run("npm", ["install", "--save-dev", packageSpec, "--registry", registry], tmpRoot);

  writeFileSync(
    join(tmpRoot, "App.weiv"),
    `<template>
  <main>
    <h1>{{ title }}</h1>
    <p>Count: {{ count }}</p>
    <button @click="inc">+1</button>
  </main>
</template>

<script lang="ts">
  let title = "Weiv Package E2E";
  let count = 0;
  function inc() {
    count += 1;
  }
</script>
`,
  );

  run("npx", ["weiv", "--help"], tmpRoot);
  run("npx", ["weiv", "compile", "emit", "app", "App.weiv", "./dist"], tmpRoot);

  run(
    "node",
    ["--input-type=module", "-e", "import('weivjs/vite').then(()=>console.log('vite export ok'))"],
    tmpRoot,
  );
  run(
    "node",
    ["--input-type=module", "-e", "import('weivjs/bun').then(()=>console.log('bun export ok'))"],
    tmpRoot,
  );

  assertExists(join(tmpRoot, "dist", "App.mjs"));
  assertExists(join(tmpRoot, "dist", "bundle.mjs"));
  assertExists(join(tmpRoot, "dist", "index.html"));
  assertExists(join(tmpRoot, "dist", "server.ts"));

  console.log(`Package E2E passed in ${tmpRoot}`);
} finally {
  if (keepTemp) {
    console.log(`Keeping temp directory for inspection: ${tmpRoot}`);
  } else {
    rmSync(tmpRoot, { recursive: true, force: true });
  }
}
