# VK Skills

[![skills.sh](https://skills.sh/b/VidhyaKumar/skills)](https://skills.sh/VidhyaKumar/skills)

Agent skills for git workflows and code cleanup. Compatible with Claude Code, Cursor, Codex, OpenCode, and other [Agent Skills](https://agentskills.io)-compatible agents.

## Skills

| Skill | Description |
| --- | --- |
| `commit-all` | Group all working tree changes into logical atomic commits. |
| `commit-staged` | Generate a commit message for staged changes and commit. |
| `create-pr` | Create a pull request with a succinct what/why/how description. |
| `review-changes` | Review staged, unstaged, and untracked changes. |
| `code-slop-check` | Simplify and refine recently modified code while preserving functionality. |
| `prose-slop-check` | Detect and remove AI-writing tells from prose while preserving the writer's voice. |
| `bro` | Restate the last message simply and without jargon. |
| `attention-kind` | ADHD-friendly replies: plain English, front-loaded answers, short by default. |
| `happy-path-first` | Implement with happy-path-first orchestration, deep modules, and type-driven invariants. |
| `fleet` | Orchestration mode: main agent plans and reviews; task-matched worker models in herdr panes do all code changes. |

## Install

Install all skills:

```bash
bunx skills add VidhyaKumar/skills --skill '*'
```

Install a specific skill:

```bash
bunx skills add VidhyaKumar/skills --skill commit-all
```

Target a specific agent:

```bash
bunx skills add VidhyaKumar/skills --skill '*' -a claude-code
```

## Credits

`attention-kind` is adapted from [attention-span](https://github.com/alexgreensh/attention-span) by [alexgreensh](https://github.com/alexgreensh).

`happy-path-first` is adapted from [code-like-luke](https://gist.github.com/Hona/53142c07c9decb735392f132ace34003) by [Hona](https://github.com/Hona).
