import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(here, "..");
const srcRoot = resolve(packageRoot, "src");
const repoRoot = resolve(packageRoot, "..", "..");
const canonicalRuntimeRoot = resolve(repoRoot, "packages", "weiv", "src", "runtime");
const distRoot = resolve(packageRoot, "dist");

rmSync(distRoot, { recursive: true, force: true });
mkdirSync(distRoot, { recursive: true });

cpSync(resolve(srcRoot, "index.mjs"), resolve(distRoot, "index.mjs"));
cpSync(resolve(srcRoot, "vite.mjs"), resolve(distRoot, "vite.mjs"));
cpSync(resolve(srcRoot, "bun.mjs"), resolve(distRoot, "bun.mjs"));
cpSync(resolve(srcRoot, "platform.mjs"), resolve(distRoot, "platform.mjs"));
cpSync(resolve(srcRoot, "managed.mjs"), resolve(distRoot, "managed.mjs"));
cpSync(resolve(srcRoot, "run-bin.mjs"), resolve(distRoot, "run-bin.mjs"));

mkdirSync(resolve(distRoot, "runtime"), { recursive: true });
transpileRuntimeTsToJs(resolve(canonicalRuntimeRoot, "index.ts"), resolve(distRoot, "runtime", "index.js"));
transpileRuntimeTsToJs(
  resolve(canonicalRuntimeRoot, "binding.ts"),
  resolve(distRoot, "runtime", "binding.js"),
);
transpileRuntimeTsToJs(resolve(canonicalRuntimeRoot, "cell.ts"), resolve(distRoot, "runtime", "cell.js"));
transpileRuntimeTsToJs(
  resolve(canonicalRuntimeRoot, "reactive-core.ts"),
  resolve(distRoot, "runtime", "reactive-core.js"),
);
transpileRuntimeTsToJs(
  resolve(canonicalRuntimeRoot, "observable.ts"),
  resolve(distRoot, "runtime", "observable.js"),
);
transpileRuntimeTsToJs(resolve(canonicalRuntimeRoot, "router.ts"), resolve(distRoot, "runtime", "router.js"));

console.log(`Built dist at ${distRoot}`);

function transpileRuntimeTsToJs(inputPath, outputPath) {
  execFileSync("bun", ["build", inputPath, "--no-bundle", "--outfile", outputPath], {
    stdio: "inherit",
  });
  const source = readFileSync(outputPath, "utf8").replace(/from\s+"(\.\/[^"\n]+)\.ts"/g, 'from "$1.js"');
  writeFileSync(outputPath, source, "utf8");
}
