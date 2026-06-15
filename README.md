# VK Skills

[![skills.sh](https://skills.sh/b/VidhyaKumar/skills)](https://skills.sh/VidhyaKumar/skills)

Agent skills for git workflows and code cleanup. Compatible with Claude Code, Cursor, Codex, OpenCode, and other [Agent Skills](https://agentskills.io)-compatible agents.

## Skills

| Skill | Description |
| --- | --- |
| `commit-all` | Group all working tree changes into logical atomic commits. |
| `commit-staged` | Generate a commit message for staged changes and commit. |
| `review-changes` | Review staged, unstaged, and untracked changes. |
| `deslopper` | Simplify and refine recently modified code while preserving functionality. |

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
  commit-all/SKILL.md
  commit-staged/SKILL.md
  review-changes/SKILL.md
  deslopper/SKILL.md
skills.sh.json
```
