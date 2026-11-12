#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sites = resolve(process.env.WEIV_SITES_REPO ?? join(root, "..", "sites"));
const version = JSON.parse(readFileSync(join(root, "packages/weiv/package.json"), "utf8")).version;
const siteVersion = JSON.parse(readFileSync(join(root, "site/site.json"), "utf8")).version;
const tag = `v${version}`;

function run(command, args, cwd = root) {
  console.log(`+ ${command} ${args.join(" ")}`);
  return execFileSync(command, args, { cwd, encoding: "utf8", stdio: ["inherit", "pipe", "inherit"] }).trim();
}

function requireEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`);
}

try {
  requireEqual(siteVersion, version, "site version");
  if (!existsSync(join(sites, "sites/weiv-dev"))) throw new Error(`sites checkout is missing: ${sites}`);
  requireEqual(run("git", ["status", "--porcelain", "--", "site"]), "", "Weiv site source status");
  requireEqual(
    run("git", ["ls-remote", "origin", "refs/heads/main"]).split("\t")[0],
    run("git", ["rev-parse", "HEAD"]),
    "published Weiv commit",
  );
  run("gh", ["release", "view", tag, "--repo", "neucine/weiv"]);
  requireEqual(
    JSON.parse(run("npm", ["view", `weivjs@${version}`, "version", "--json"])),
    version,
    "published npm version",
  );

  requireEqual(run("git", ["status", "--porcelain"], sites), "", "sites checkout status");
  run("git", ["fetch", "origin", "main"], sites);
  requireEqual(
    run("git", ["rev-parse", "HEAD"], sites),
    run("git", ["rev-parse", "origin/main"], sites),
    "sites checkout commit",
  );

  run("npm", ["run", "sync:weiv"], sites);
  const lock = JSON.parse(readFileSync(join(sites, "sites/weiv-dev/content.lock.json"), "utf8"));
  requireEqual(lock.version, version, "site content lock version");
  requireEqual(lock.source.commit, run("git", ["rev-parse", "HEAD"]), "site content lock commit");
  requireEqual(lock.source.dirty, false, "site content lock dirty flag");
  run("npm", ["run", "build:weiv"], sites);

  run("git", ["add", "--", "sites/weiv-dev"], sites);
  if (run("git", ["diff", "--cached", "--name-only"], sites)) {
    run("git", ["commit", "-m", `Sync weiv.dev to ${version}`], sites);
    run("git", ["push", "origin", "HEAD:main"], sites);
  }
  requireEqual(run("git", ["status", "--porcelain"], sites), "", "sites status after sync");
  run("npm", ["run", "deploy:weiv"], sites);
  run("npm", ["run", "verify:weiv"], sites);
  console.log(`weiv.dev synced to ${version}`);
} catch (error) {
  console.error(`weiv site sync: ${error.message}`);
  process.exitCode = 1;
}
