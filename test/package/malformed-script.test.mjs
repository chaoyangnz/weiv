import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const temp = mkdtempSync(join(tmpdir(), "weiv-malformed-script-"));
try {
  const source = join(temp, "App.weiv");
  writeFileSync(source, '<template><button @click="click">Go</button></template><script lang="ts">let id = "a"; let rows: any[] = []; function click() { rows.some((row: any) => row.id === id; }</script>');
  const result = spawnSync(resolve(root, "cyna-out/bin/weiv"), ["compile", "emit", "js", source], { encoding: "utf8" });
  assert.notEqual(result.status, 0, "malformed TypeScript must fail compilation");
  assert.match(result.stderr, /script\.syntax.*\[script_facts\].*fatal/);
  assert.match(result.stderr, /script\.syntax \[script_facts\] \[1:\d+\]/);
  assert.equal(result.stdout, "");
} finally {
  rmSync(temp, { recursive: true, force: true });
}

console.log("Malformed TypeScript failed with a source location");
