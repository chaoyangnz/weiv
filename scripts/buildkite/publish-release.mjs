#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

if (process.env.RELEASE_PUBLISH !== "1") throw Error("Set RELEASE_PUBLISH=1 on the manual release build");
const root = process.cwd();
const directory = join(root, "dist/release/collected");
const manifest = JSON.parse(readFileSync(join(directory, "manifest.json")));
const run = (cmd, args, options = {}) => execFileSync(cmd, args, { cwd: root, encoding: "utf8", ...options }).trim();
if (manifest.commit !== process.env.BUILDKITE_COMMIT || run("git", ["rev-parse", "HEAD"]) !== manifest.commit)
  throw Error("Release manifest is for a different commit");
if (process.env.BUILDKITE_BRANCH !== `release/${manifest.tag}`) throw Error("Release branch does not match manifest");
if (run("git", ["status", "--porcelain"])) throw Error("Release checkout is dirty");
for (const item of manifest.outputs) {
  const file = join(directory, item.name);
  if (!existsSync(file) || createHash("sha256").update(readFileSync(file)).digest("hex") !== item.sha256)
    throw Error(`Release artifact changed: ${item.name}`);
}
const token = process.env.NPM_TOKEN;
if (!token) throw Error("NPM_TOKEN is required for publication");
const configRoot = mkdtempSync(join(tmpdir(), "weiv-npm-release-"));
const config = join(configRoot, "npmrc");
writeFileSync(config, `registry=https://registry.npmjs.org/\n//registry.npmjs.org/:_authToken=${token}\n`, { mode: 0o600 });
const env = { ...process.env, NPM_CONFIG_USERCONFIG: config, npm_config_offline: "false" };
try {
  const existingTag = run("git", ["tag", "--list", manifest.tag]);
  if (existingTag) {
    if (run("git", ["rev-list", "-n", "1", manifest.tag]) !== manifest.commit)
      throw Error("Release tag points to another commit");
  } else {
    run("git", ["tag", "-a", manifest.tag, "-m", manifest.tag, manifest.commit]);
    run("git", ["-c", "credential.helper=!gh auth git-credential", "push", "origin", `refs/tags/${manifest.tag}`], { stdio: "inherit", env });
  }
  const platformPackages = manifest.outputs.filter(item => !item.name.startsWith("weivjs-"));
  const main = manifest.outputs.find(item => item.name === `weivjs-${manifest.version}.tgz`);
  if (!main || platformPackages.length !== manifest.platforms.length) throw Error("Incomplete release packages");
  for (const item of [...platformPackages, main]) {
    const file = join(directory, item.name);
    const metadata = JSON.parse(run("tar", ["-xOzf", file, "package/package.json"]));
    const packageId = `${metadata.name}@${metadata.version}`;
    const localIntegrity = `sha512-${createHash("sha512").update(readFileSync(file)).digest("base64")}`;
    let publishedIntegrity = "";
    try {
      publishedIntegrity = run("npm", ["view", packageId, "dist.integrity", "--json"], { env }).replace(/^"|"$/g, "");
    } catch {
      // The package does not exist yet.
    }
    if (publishedIntegrity && publishedIntegrity !== localIntegrity)
      throw Error(`Registry package differs from verified artifact: ${packageId}`);
    if (!publishedIntegrity) run("npm", ["publish", file, "--access", "public", "--ignore-scripts"], { env, stdio: "inherit" });
    console.log(`Published and checked ${packageId}`);
  }
} finally {
  rmSync(configRoot, { recursive: true, force: true });
}
