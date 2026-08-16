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

## Layout

```
skills/
  commit-all/
    SKILL.md
    agents/
      openai.yaml
  commit-staged/
    SKILL.md
    agents/
      openai.yaml
  create-pr/
    SKILL.md
    agents/
      openai.yaml
  review-changes/
    SKILL.md
    agents/
      openai.yaml
  code-slop-check/
    SKILL.md
    agents/
      openai.yaml
  prose-slop-check/
    SKILL.md
    eval.md
    references/
      tells.md
      voices.md
  happy-path-first/SKILL.md
  attention-kind/SKILL.md
  bro/SKILL.md
  fleet/
    SKILL.md
    references/
      worker-brief.md
    scripts/
      fleet-guard.sh
      fleet-watch.sh
skills.sh.json
```
