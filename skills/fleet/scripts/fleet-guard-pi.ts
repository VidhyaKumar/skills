// fleet-guard-pi.ts — Pi harness guard for fleet mode.
// Mirrors fleet-guard.sh: inert unless <repo-root>/.fleet/active exists.
// Blocks the fleet-manager's file mutations so task work goes to fleet-workers.
// Install: copy or symlink into ~/.pi/agent/extensions/ (global, recommended)
// or .pi/extensions/ (project-local). Pi auto-discovers both.
// Bash blocking is heuristic: it catches common write patterns, not all of them.
import { existsSync } from "node:fs";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function fleetRoot(): string | null {
  let dir = process.cwd();
  for (;;) {
    if (existsSync(join(dir, ".fleet", "active"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

const DENY_SUFFIX =
  "Dispatch a fleet-worker instead (run /fleet to resume orchestrating). " +
  "Only the user can deactivate (by saying 'fleet off').";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    if (fleetRoot()) ctx.ui.setStatus("fleet", "fleet mode ON — orchestrate, don't edit");
  });

  pi.on("tool_call", async (event) => {
    const root = fleetRoot();
    if (!root) return;
    const deny = (what: string) => ({
      block: true,
      reason: `fleet mode active in ${root}: ${what} ${DENY_SUFFIX}`,
    });

    const name = event.toolName;
    if (name === "write" || name === "edit" || name === "multi_edit" || name === "notebook_edit") {
      const input = event.input as { path?: string; file_path?: string };
      const target = input.path ?? input.file_path ?? "";
      // resolve() normalizes any ".." segments before the exemption check
      const abs = isAbsolute(target) ? resolve(target) : resolve(process.cwd(), target);
      if (abs.startsWith(join(root, ".fleet") + sep)) return;
      return deny(`direct file edits are blocked (${name} on ${target}).`);
    }

    if (name === "bash") {
      const cmd = String((event.input as { command?: string }).command ?? "");
      // Replace quoted segments with a placeholder so quoted text (e.g. a '>'
      // inside a git --format string) can't trip the heuristics. A placeholder,
      // not deletion: `echo x > "file"` must still look like a redirection.
      const stripped = cmd.replace(/'[^']*'/g, "Q").replace(/"[^"]*"/g, "Q");
      // Nested shells (bash -c '...') execute their quoted payload, so stripping
      // would let a smuggled redirect through — check those against the raw
      // command instead (conservative: quoted '>' may false-positive there).
      const check = /(^|[;&|\s])(bash|sh|zsh|dash|ksh|env)\s[^;&|]*-[a-zA-Z]*c(\s|$)/.test(stripped)
        ? cmd
        : stripped;
      // In-place editors and tee are always writes.
      if (/(^|[;&|\s'"])(sed\s+-[a-zA-Z]*i|perl\s+-[a-zA-Z]*i|tee\s)/.test(check)) {
        return deny("mutating shell command blocked (in-place edit/tee).");
      }
      // Redirection into files, unless the target is .fleet/, /tmp, or /dev/null.
      if (/>>?\s*[^&|\s]/.test(check) && !/>>?\s*([^\s]*\.fleet\/|\/tmp\/|\/dev\/null)/.test(check)) {
        return deny("shell redirection into a file blocked.");
      }
    }
  });
}
