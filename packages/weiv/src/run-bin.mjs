import { spawn } from "node:child_process";
import { resolveWeivBinaryPath } from "./platform.mjs";
import { fileURLToPath } from "node:url";

export function runWeivCli(args) {
  const bin = resolveWeivBinaryPath();
  const child = spawn(bin, ["--runtime-dir", fileURLToPath(new URL("./runtime", import.meta.url)), ...args], {
    stdio: "inherit",
    env: process.env
  });

  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 1);
  });
}
