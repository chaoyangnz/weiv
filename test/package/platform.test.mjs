import assert from "node:assert/strict";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveWeivBinaryPath } from "../../packages/weiv/src/platform.mjs";
import { resolveWeivBinaryPath as resolveBuiltBinaryPath } from "../../packages/weiv/dist/platform.mjs";

const previousBinary = process.env.WEIV_BINARY_PATH;
try {
  delete process.env.WEIV_BINARY_PATH;
  const repoRoot = fileURLToPath(new URL("../../", import.meta.url));
  const expectedBinary = resolve(
    repoRoot,
    "cyna-out/bin",
    process.platform === "win32" ? "weiv.exe" : "weiv",
  );
  assert.equal(resolveWeivBinaryPath(), expectedBinary);
  assert.equal(resolveBuiltBinaryPath(), expectedBinary);

  process.env.WEIV_BINARY_PATH = process.execPath;
  assert.equal(resolveWeivBinaryPath(), process.execPath);
  assert.equal(resolveBuiltBinaryPath(), process.execPath);
} finally {
  if (previousBinary === undefined) delete process.env.WEIV_BINARY_PATH;
  else process.env.WEIV_BINARY_PATH = previousBinary;
}

console.log("Source checkout binary selection and explicit override passed");
