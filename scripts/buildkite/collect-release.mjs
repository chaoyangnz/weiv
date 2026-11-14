#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, copyFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const commit = process.env.BUILDKITE_COMMIT;
const branch = process.env.BUILDKITE_BRANCH;
const version = branch?.match(/^release\/v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)$/)?.[1];
if (!commit || !version) throw Error("Expected a release branch and Buildkite commit");
const platforms = process.argv.slice(2);
if (!platforms.length) throw Error("Pass the candidate platform names");
const sha256 = file => createHash("sha256").update(readFileSync(file)).digest("hex");
const release = join(root, "dist/release/collected");
mkdirSync(release, { recursive: true });
const outputs = new Map();
const main = `weivjs-${version}.tgz`;
for (const platform of platforms) {
  const source = join(root, "dist/release/candidates", platform);
  const plan = JSON.parse(readFileSync(join(source, "dist/release/state/plan.json")));
  const verify = JSON.parse(readFileSync(join(source, "dist/release/state/verify.json")));
  if (plan.commit !== commit || verify.commit !== commit || plan.version !== version || verify.version !== version)
    throw Error(`Candidate ${platform} belongs to another release`);
  const target = plan.targets?.[0];
  if (!(platform === "macos" ? target?.startsWith("darwin-") : target === (platform === "linux" ? "linux-x64" : "win32-x64")))
    throw Error(`Candidate ${platform} has unexpected host: ${target}`);
  if (plan.gates.some(name => !verify.gates.some(gate => gate.name === name && gate.result === "passed")))
    throw Error(`Candidate ${platform} has an incomplete gate`);
  if (verify.outputs.length !== 2 || !verify.outputs.some(item => item.name === main))
    throw Error(`Candidate ${platform} has unexpected packages`);
  for (const item of verify.outputs) {
    const file = join(source, "dist/release/artifacts", item.name);
    if (!existsSync(file) || sha256(file) !== item.sha256) throw Error(`Candidate hash mismatch: ${platform}/${item.name}`);
    const previous = outputs.get(item.name);
    if (previous && previous.sha256 !== item.sha256) throw Error(`Cross-platform package mismatch: ${item.name}`);
    if (!previous) {
      copyFileSync(file, join(release, item.name));
      outputs.set(item.name, { name: item.name, sha256: item.sha256 });
    }
  }
}
if (outputs.size !== platforms.length + 1) throw Error("A platform package is missing or duplicated");
const manifest = { version, tag: `v${version}`, commit, platforms, outputs: [...outputs.values()] };
writeFileSync(join(release, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
writeFileSync(join(release, "SHA256SUMS"), manifest.outputs.map(item => `${item.sha256}  ${item.name}`).join("\n") + "\n");
console.log(JSON.stringify(manifest, null, 2));
