import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const repoRoot = process.cwd();
const tmp = mkdtempSync(join(tmpdir(), "weiv-release-check-"));
const tarballs = [];

function run(cmd, args, cwd, env = process.env) {
  execFileSync(cmd, args, { cwd, env, stdio: "inherit" });
}

function pack(dir) {
  const raw = execFileSync("npm", ["pack", "--json", dir], { cwd: repoRoot, encoding: "utf8" });
  const jsonStart = raw.indexOf("[");
  const parsed = JSON.parse(raw.slice(jsonStart));
  const filename = parsed[0]?.filename;
  if (!filename) throw new Error(`Failed to parse pack output for ${dir}`);
  const full = resolve(repoRoot, filename);
  tarballs.push(full);
  return full;
}

function detectPlaceholder(platformTar) {
  const inspectDir = join(tmp, "inspect");
  mkdirSync(inspectDir, { recursive: true });
  run("tar", ["-xzf", platformTar, "-C", inspectDir], repoRoot);
  const pkgDir = join(inspectDir, "package");
  const candidates = [join(pkgDir, "bin", "weiv"), join(pkgDir, "bin", "weiv.exe")];
  for (const file of candidates) {
    let content = null;
    try {
      content = readFileSync(file);
    } catch {
      continue;
    }
    const isElf = content.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]));
    const isMachO =
      content.subarray(0, 4).equals(Buffer.from([0xcf, 0xfa, 0xed, 0xfe])) ||
      content.subarray(0, 4).equals(Buffer.from([0xfe, 0xed, 0xfa, 0xcf]));
    const isPe = content.subarray(0, 2).toString("ascii") === "MZ";
    if (!isElf && !isMachO && !isPe) {
      throw new Error(
        `Placeholder binary detected in ${platformTar}. Replace with real platform binary before publish.`,
      );
    }
    return;
  }
  throw new Error(`No platform binary found in ${platformTar}`);
}

try {
  const mainTar = pack("./packages/weiv");
  const version = JSON.parse(readFileSync(join(repoRoot, "packages/weiv/package.json"), "utf8")).version;
  const platformDirs = ["weiv-darwin-arm64", "weiv-linux-x64-gnu", "weiv-win32-x64-msvc"];
  const platformTars = platformDirs
    .filter(
      name =>
        (name !== "weiv-linux-x64-gnu" || process.platform === "linux") &&
        (name !== "weiv-win32-x64-msvc" || process.platform === "win32") &&
        JSON.parse(readFileSync(join(repoRoot, "packages", name, "package.json"), "utf8")).version ===
          version,
    )
    .map(name => pack(`./packages/${name}`));

  for (const t of platformTars) detectPlaceholder(t);

  const app = join(tmp, "app");
  mkdirSync(app, { recursive: true });
  run("npm", ["init", "-y"], app);
  run("npm", ["install", "--omit=optional", mainTar], app);
  run(
    "node",
    ["--input-type=module", "-e", "import('weivjs/vite').then(()=>console.log('vite types/export ok'))"],
    app,
  );
  run(
    "node",
    ["--input-type=module", "-e", "import('weivjs/bun').then(()=>console.log('bun types/export ok'))"],
    app,
  );

  console.log("Release check completed (note: platform binaries must be real non-placeholder artifacts).");
} finally {
  rmSync(tmp, { recursive: true, force: true });
  for (const tar of tarballs) rmSync(tar, { force: true });
}
