import { existsSync } from "fs";
import { logger } from "./logger.js";

/** Run a `gh` CLI command and return stdout. Throws on non-zero exit. */
export async function runGh(args: string[]): Promise<string> {
  const ghPath = findGh();
  const proc = Bun.spawn([ghPath, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (exitCode !== 0) {
    throw new Error(`gh ${args[0]} failed (exit ${exitCode}): ${stderr.trim()}`);
  }
  return stdout.trim();
}

function findGh(): string {
  const candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  return "gh";
}
