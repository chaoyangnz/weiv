import { cpSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const repoRoot = process.cwd();
const weivBin = resolve(repoRoot, "cyna-out/bin/weiv");
const tempRoot = mkdtempSync(join(tmpdir(), "weiv-npm-smoke-"));
const packedTarballs = [];

function run(cmd, args, cwd, env = process.env) {
  execFileSync(cmd, args, {
    cwd,
    env,
    stdio: "inherit"
  });
}

function runCapture(cmd, args, cwd) {
  return execFileSync(cmd, args, {
    cwd,
    encoding: "utf8"
  }).trim();
}

function pack(dir) {
  const raw = runCapture("npm", ["pack", "--json", dir], repoRoot);
  const jsonStart = raw.indexOf("[");
  if (jsonStart === -1) {
    throw new Error(`Could not find JSON payload in npm pack output for ${dir}: ${raw}`);
  }
  const jsonCandidate = raw.slice(jsonStart).trim();
  const parsed = JSON.parse(jsonCandidate);
  const name = Array.isArray(parsed) ? parsed[0]?.filename : null;
  if (!name) {
    throw new Error(`Could not parse npm pack filename for ${dir}: ${raw}`);
  }
  const tarballPath = resolve(repoRoot, name);
  packedTarballs.push(tarballPath);
  return tarballPath;
}

function unpackTarball(tarballPath, destDir) {
  mkdirSync(destDir, { recursive: true });
  run("tar", ["-xzf", tarballPath, "-C", destDir], repoRoot);
  const packageDir = join(destDir, "package");
  if (!packageDir) throw new Error(`Failed to unpack tarball: ${tarballPath}`);
  return packageDir;
}

function currentPlatformPackageDir() {
  if (process.platform === "darwin" && process.arch === "arm64") {
    return "./packages/weiv-darwin-arm64";
  }
  return null;
}

try {
  const appRoot = join(tempRoot, "app");
  const nodeModules = join(appRoot, "node_modules");
  const scopedNodeModules = join(nodeModules, "@weivjs");
  mkdirSync(scopedNodeModules, { recursive: true });

  const weivTar = pack("./packages/weiv");
  const weivUnpackRoot = join(tempRoot, "weiv-unpack");
  const weivPkgDir = unpackTarball(weivTar, weivUnpackRoot);
  cpSync(weivPkgDir, join(nodeModules, "weivjs"), { recursive: true });

  const platformDir = currentPlatformPackageDir();
  if (platformDir) {
    const platformTar = pack(platformDir);
    const platformUnpackRoot = join(tempRoot, "platform-unpack");
    const platformPkgDir = unpackTarball(platformTar, platformUnpackRoot);
    const platformPkgJson = JSON.parse(
      runCapture("node", ["-e", `process.stdout.write(JSON.stringify(require('${platformPkgDir.replace(/\\/g, "\\\\")}/package.json')))`], repoRoot)
    );
    const platformName = platformPkgJson.name.split("/")[1];
    cpSync(platformPkgDir, join(scopedNodeModules, platformName), { recursive: true });
  }

  run("node", ["--input-type=module", "-e", "import('weivjs/vite').then(()=>console.log('vite export ok'))"], appRoot);
  run("node", ["--input-type=module", "-e", "import('weivjs/bun').then(()=>console.log('bun export ok'))"], appRoot);

  run(
    "node",
    [join(nodeModules, "weivjs", "bin", "weiv.mjs"), "--help"],
    appRoot,
    {
      ...process.env,
      WEIV_BINARY_PATH: weivBin,
    }
  );

  const boundaryFixture = join(appRoot, "ExternalCallback.weiv");
  writeFileSync(boundaryFixture, `<template><p>{{ count }}</p></template>\n<script lang="ts">let count = 0; window.addEventListener("message", () => { count += 1; });</script>\n`);
  const emitted = execFileSync("node", [join(nodeModules, "weivjs", "bin", "weiv.mjs"), "emit", "js", boundaryFixture], {
    cwd: appRoot,
    encoding: "utf8",
    env: { ...process.env, WEIV_BINARY_PATH: "" },
  });
  if (!emitted.includes("__weiv_createCellScope") || emitted.includes("const weivUpdate =")) {
    throw new Error("Packed platform binary did not emit managed component state");
  }

  console.log(`Smoke test completed in ${tempRoot}`);
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
  for (const tarball of packedTarballs) {
    rmSync(tarball, { force: true });
  }
}
