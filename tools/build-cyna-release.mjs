import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const compiler = process.env.CYNA || "cyna";
const manifest = resolve(repoRoot, "cyna.release.toml");
const output = resolve(repoRoot, "cyna-out", "bin", process.platform === "win32" ? "weiv.exe" : "weiv");
const env = { ...process.env };
const platformPackage =
  process.platform === "darwin" && process.arch === "arm64"
    ? resolve(repoRoot, "packages", "weiv-darwin-arm64", "bin", "weiv")
    : null;

if (process.platform === "darwin" && !env.SDKROOT) {
  env.SDKROOT = execFileSync("xcrun", ["--show-sdk-path"], { encoding: "utf8" }).trim();
}

mkdirSync(dirname(output), { recursive: true });
execFileSync(
  "cargo",
  [
    "build",
    "--release",
    "--locked",
    "--manifest-path",
    resolve(repoRoot, "libs", "parser-backend", "Cargo.toml"),
  ],
  {
    cwd: repoRoot,
    env,
    stdio: "inherit",
  },
);
execFileSync(compiler, ["build", manifest, "--output", output], {
  cwd: repoRoot,
  env,
  stdio: "inherit",
});
if (platformPackage) copyFileSync(output, platformPackage);

console.log(`Built Cyna release binary at ${output}`);
if (platformPackage) console.log(`Updated platform package binary at ${platformPackage}`);
