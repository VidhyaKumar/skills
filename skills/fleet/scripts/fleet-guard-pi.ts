// fleet-guard-pi.ts — Pi harness guard for fleet mode.
// Runs fleet-guard.sh on Pi's write/edit/bash calls, so the allowlist lives in
// exactly one place. Inert unless <repo-root>/.fleet/active exists.
// Install: copy or symlink into ~/.pi/agent/extensions/ (global, recommended)
// or .pi/extensions/ (project-local). Pi auto-discovers both. A copy must sit
// next to fleet-guard.sh (or set FLEET_GUARD to its path). Needs bash and jq.
import { spawnSync } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const GUARD =
  process.env.FLEET_GUARD ??
  join(dirname(realpathSync(fileURLToPath(import.meta.url))), "fleet-guard.sh");

function armed(): boolean {
  let dir = process.cwd();
  for (;;) {
    if (existsSync(join(dir, ".fleet", "active"))) return true;
    const parent = dirname(dir);
    if (parent === dir) return false;
    dir = parent;
  }
}

// Pi tool name -> hook payload tool name. Pi has no notebook or patch tool;
// a custom or MCP-provided write tool is outside this guard.
const TOOLS: Record<string, string> = { write: "Write", edit: "Edit", bash: "Bash" };

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    if (armed()) ctx.ui.setStatus("fleet", "fleet mode ON — orchestrate, don't edit");
  });

  pi.on("tool_call", async (event) => {
    const tool = TOOLS[event.toolName];
    if (!tool || !armed()) return;
    const input = (event.input ?? {}) as { path?: string; command?: string };
    const payload = JSON.stringify({
      tool_name: tool,
      cwd: process.cwd(),
      tool_input: tool === "Bash" ? { command: input.command ?? "" } : { file_path: input.path ?? "" },
    });
    const r = spawnSync("bash", [GUARD], { input: payload, encoding: "utf8" });
    if (r.status === 0) return;
    // Fail closed: a missing or crashing guard blocks with its own message.
    return { block: true, reason: (r.stderr || r.error?.message || "fleet-guard.sh failed").trim() };
  });
}
