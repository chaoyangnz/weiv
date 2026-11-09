import { accessSync, constants, existsSync, realpathSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);

const PLATFORM_PACKAGES = {
  "darwin-arm64": "@weivjs/weiv-darwin-arm64",
  "darwin-x64": "@weivjs/weiv-darwin-x64",
  "linux-x64": "@weivjs/weiv-linux-x64-gnu",
  "linux-arm64": "@weivjs/weiv-linux-arm64-gnu",
  "win32-x64": "@weivjs/weiv-win32-x64-msvc"
};

export function resolveWeivBinaryPath() {
  if (process.env.WEIV_BINARY_PATH) {
    assertExecutable(process.env.WEIV_BINARY_PATH, "WEIV_BINARY_PATH");
    return process.env.WEIV_BINARY_PATH;
  }

  const localBinary = resolveSourceCheckoutBinary();
  if (localBinary) return localBinary;

  const key = `${process.platform}-${process.arch}`;
  const packageName = PLATFORM_PACKAGES[key];
  if (!packageName) {
    throw new Error(
      `Unsupported platform for weiv binary: ${key}. Set WEIV_BINARY_PATH to continue.`
    );
  }

  try {
    const pkgJsonPath = require.resolve(`${packageName}/package.json`);
    const binaryName = process.platform === "win32" ? "weiv.exe" : "weiv";
    const candidate = join(pkgJsonPath, "..", "bin", binaryName);
    assertExecutable(candidate, packageName);
    return candidate;
  } catch (error) {
    throw new Error(
      [
        `Could not resolve weiv binary for ${key}.`,
        `Expected optional dependency: ${packageName}.`,
        `Try reinstalling without --omit=optional, or set WEIV_BINARY_PATH.`,
        `Original error: ${error instanceof Error ? error.message : String(error)}`
      ].join("\n")
    );
  }
}

function resolveSourceCheckoutBinary() {
  const moduleDir = dirname(fileURLToPath(import.meta.url));
  const packagePath = resolve(moduleDir, "../package.json");
  const checkoutRoot = resolve(moduleDir, "../../..");
  const checkoutPackagePath = join(checkoutRoot, "packages", "weiv", "package.json");
  if (!existsSync(checkoutPackagePath) || realpathSync(packagePath) !== realpathSync(checkoutPackagePath)) {
    return null;
  }

  const binaryName = process.platform === "win32" ? "weiv.exe" : "weiv";
  const candidate = join(checkoutRoot, "zig-out", "bin", binaryName);
  assertExecutable(candidate, "Weiv source checkout (run npm run build:cyna or set WEIV_BINARY_PATH)");
  return candidate;
}

function assertExecutable(path, source) {
  try {
    accessSync(path, constants.R_OK | constants.X_OK);
  } catch {
    throw new Error(`Binary from ${source} is not executable: ${path}`);
  }
}
