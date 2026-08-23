// fleet-guard-pi.ts — Pi harness guard for fleet mode.
// Mirrors fleet-guard.sh: inert unless <repo-root>/.fleet/active exists.
// Blocks the fleet-manager's file mutations so task work goes to fleet-workers.
// Install: copy or symlink into ~/.pi/agent/extensions/ (global, recommended)
// or .pi/extensions/ (project-local). Pi auto-discovers both.
// Bash is checked against a read-only allowlist: every command in the pipeline
// must be one we know cannot write, and anything unrecognized is refused.
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
    if (name === "write" || name === "edit") {
      const input = event.input as { path?: string };
      const target = input.path ?? "";
      // resolve() normalizes any ".." segments before the exemption check
      const abs = isAbsolute(target) ? resolve(target) : resolve(process.cwd(), target);
      if (abs.startsWith(join(root, ".fleet") + sep)) return;
      return deny(`direct file edits are blocked (${name} on ${target}).`);
    }

    if (name === "bash") {
      const cmd = String((event.input as { command?: string }).command ?? "");
      // Three views of the command, each for a different question. See
      // fleet-guard.sh for the rationale; this mirrors it exactly.
      const unq = cmd
        .replace(/(>>?)\s*"([^"]*)"/g, "$1 $2")
        .replace(/(>>?)\s*'([^']*)'/g, "$1 $2");
      const stripped = unq.replace(/'[^']*'/g, "Q").replace(/"[^"]*"/g, "Q");
      // Quoted spans holding a shell metacharacter collapse to Q first —
      // deleting those quotes would turn `cut -d"|"` into a real pipe.
      const bare = cmd
        .replace(/"[^"]*[;|&$`][^"]*"/g, "Q")
        .replace(/'[^']*[;|&$`][^']*'/g, "Q")
        .replace(/['"]/g, "");

      // Allowlist, not blocklist. A blocklist of shell verbs cannot be made
      // sound — /bin/rm, \rm, `echo ... | bash` and `python -c"..."` all reach
      // the same write. Anything unrecognized is refused.
      const ALLOW = new Set(
        // awk/sed/yq are absent on purpose: awk has system() and `print > file`,
        // sed has `w file`, yq has -i. They are interpreters that can write,
        // same class as the perl/python we already refuse. less/more shell out
        // via `!`.
        `cat head tail ls tree find grep rg egrep fgrep wc sort uniq cut tr
jq diff comm join column basename dirname realpath readlink stat file du df ps
echo printf pwd date test true false which type herdr git sleep`.split(/\s+/),
      );

      if (/\$\(|`/.test(stripped)) {
        return deny("command substitution blocked (it hides the command being run).");
      }
      if (/(^|[;&|\s'"])(sed\s+(-[a-zA-Z]*i|--in-place)|perl\s+(-[a-zA-Z]*i|--in-place)|tee\s)/.test(stripped)) {
        return deny("mutating shell command blocked (in-place edit/tee).");
      }
      // find and sort are read-only tools with write actions bolted on.
      if (
        /(^|[;&|\s'"])find\s/.test(stripped) &&
        /\s-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)(\s|$)/.test(stripped)
      ) {
        return deny("find action that writes or runs a command blocked.");
      }
      if (/(^|[;&|\s'"])sort\s/.test(stripped) && /\s(-o|--output)(\s|=)/.test(stripped)) {
        return deny("sort writing to a file blocked.");
      }

      // Neutralise fd duplication (2>&1, >&2, &>log) so its '&' is not
      // mistaken for a background separator, then split the pipeline.
      const segments = bare
        .replace(/[0-9]*>&[0-9-]+/g, "RD")
        .replace(/&>>?/g, "RD")
        .split(/\|\||&&|[;|&]/);

      for (const seg of segments) {
        const tokens = seg.trim().split(/\s+/).filter(Boolean);
        while (tokens.length && (/=/.test(tokens[0]) || ["nohup", "timeout", "time", "builtin", "command", "env"].includes(tokens[0]))) {
          tokens.shift();
        }
        if (!tokens.length) continue;
        const base = tokens[0].split("/").pop() ?? "";

        if (/^fleet-.*\.sh$/.test(base)) continue;

        if (["bash", "sh", "zsh", "dash", "ksh"].includes(base)) {
          // Running a named script is fine. -c smuggles a command inline, and
          // a shell with no script argument reads one from stdin, which is how
          // `echo "rm -rf src" | bash` gets there.
          let script = "";
          for (const tok of tokens.slice(1)) {
            if (/^(-c|--command)/.test(tok)) return deny("shell -c blocked.");
            if (/^-s/.test(tok)) return deny(`${base} reading a script from stdin blocked.`);
            if (!tok.startsWith("-")) { script = tok; break; }
          }
          if (!script) return deny(`${base} with no script argument reads from stdin; blocked.`);
          continue;
        }

        if (base === "git") {
          // git is dual-use: allow only the read-only side, plus the merge the
          // fleet-manager performs itself. --git-dir/--work-tree/-c are refused
          // because they re-point git at another tree or rewrite its config.
          if (!/(^|\s)git\s+(--no-pager\s+|-C\s+[^\s-]\S*\s+)*(diff|log|status|show|rev-parse|rev-list|merge-base|ls-files|ls-tree|cat-file|blame|describe|shortlog|symbolic-ref|for-each-ref|branch|worktree|merge)(\s|$)/.test(seg)) {
            return deny(`git subcommand not on the fleet allowlist (${seg.trim()}).`);
          }
          if (/\sbranch\s.*(-[dDmM]|--delete|--move|--force)/.test(seg)) {
            return deny("mutating git branch blocked.");
          }
          if (/\sworktree\s.*(add|remove|prune|move|repair)/.test(seg)) {
            return deny("mutating git worktree blocked (use fleet-task.sh).");
          }
          continue;
        }

        if (!ALLOW.has(base)) {
          return deny(
            `'${base}' is not on the fleet read-only allowlist. If this is genuinely read-only, ask the user to widen the list; otherwise dispatch a fleet-worker.`,
          );
        }
      }

      // An allowlisted command can still write through a redirect.
      for (const m of stripped.matchAll(/>>?\s*([^&|;\s]+)/g)) {
        const target = m[1];
        if (target === "/dev/null" || target.startsWith("/tmp/")) continue;
        const abs = isAbsolute(target) ? resolve(target) : resolve(process.cwd(), target);
        if (abs.startsWith(join(root, ".fleet") + sep)) continue;
        return deny(`shell redirection into a file blocked (${target}).`);
      }
    }
  });
}
