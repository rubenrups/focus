# focus-orchestrator

A Claude Code skill that sets up a personal "focus orchestrator": it keeps you on the task you started, nudges you when you drift, and surfaces work that is not tracked anywhere else.

Instead of shipping a fixed setup, the skill **interviews you and builds one tailored to you**.

## What it sets up

| Piece | Purpose |
|---|---|
| `focus.md` board | One source of truth: **Now** (single task + done-when), **Open**, **Parked**, **Log** |
| Morning brief | Weekday summary of your open work, ending with "what is the ONE thing today?" |
| Check-ins | Optional nudges when you switch tasks, have too many open, or a task goes idle |
| End-of-day recap | What got done, what carries over, what is left uncommitted |
| Repo scanner | Read-only scan of local git repos for uncommitted or unpushed work that has no ticket or session |

You choose how pushy it is (quiet, moderate, pushy), your work hours, and your task sources (chat, Trello, issues, other sessions).

## Install

This repo works as a plain skill (via the `skills` CLI) and as a Claude Code plugin with its own marketplace manifest.

### With the skills CLI (recommended)

```bash
npx skills add rubenrups/focus
```

The CLI finds `skills/focus-orchestrator/SKILL.md`, copies the whole folder (including `scan-repos.ps1` and `commands/focus.md`) into `~/.agents/skills/`, and links it into `~/.claude/skills/`. Update later with `npx skills update`. Then ask Claude to set up your focus orchestrator, or run `/focus-orchestrator`; setup installs the short `/focus` command.

### As a Claude Code plugin

In Claude Code:

```text
/plugin marketplace add rubenrups/focus
/plugin install focus-orchestrator@rubenrups
```

Then run the skill with `/focus-orchestrator:focus-orchestrator` (or just ask Claude to set up your focus orchestrator). Setup installs the short `/focus` command for you.

### Try it locally without installing

```bash
git clone https://github.com/rubenrups/focus.git
claude --plugin-dir ./focus
```

### Manual copy

Copy `skills/focus-orchestrator/` to `~/.claude/skills/focus-orchestrator/` (or a project's `.claude/skills/`) and invoke `/focus-orchestrator`. Keep all three files together: `SKILL.md`, `scan-repos.ps1` and `commands/focus.md`.

### Updating a plugin install

```text
/plugin marketplace update rubenrups
```

Pick one route per machine. Installing both the skill and the plugin gives you two copies.

## Requirements

- Claude Code with scheduled tasks available (they run while the app is open; a missed run fires on next launch)
- PowerShell 7 (`pwsh`) for `scan-repos.ps1`; port it to bash on macOS/Linux if needed
- Optional: a read-only API key for your task source, kept in an env file outside any repo

## The repo scanner

`scan-repos.ps1` only runs read-only git commands (`status`, `rev-parse`, `rev-list`, `log`). It never commits, pushes or modifies anything.

```powershell
.\scan-repos.ps1 -Roots 'D:\dev' -Depth 3
.\scan-repos.ps1 -Repos 'C:\path\to\one\repo'
```

| Parameter | Meaning |
|---|---|
| `-Roots` | Folders to search for repos |
| `-Repos` | Individual repos to include |
| `-Depth` | How deep under each root to look (default 4) |
| `-Exclude` | Substrings; any path containing one is skipped |
| `-Out` | Where to write the Markdown report |

## Privacy and safety

- **Consent first:** the skill asks where your code lives and scans only the locations you approve. It never searches your machine on its own.
- **Metadata only:** it reads git state, not your source files, `.env` files or secrets.
- **Read-only everywhere:** no commits, pushes, merges, or writes to Trello or other services.
- **No secrets in output:** credentials are referenced by env file and variable name, never printed or stored.
- `focus.md` and `repo-scan.md` contain your tasks and local paths, so they are git-ignored.

## The dashboard (optional)

Setup can publish a private dashboard page so the scheduled briefs stay at a few lines and the detail lives on one screen:

- **Now** with its done-when and elapsed time
- **Open** tasks with source (Trello, session, repo) and idle age
- **Repos needing attention**, ranked by uncommitted files, with unpushed counts and a flag on work that has no card or session
- **Parked** ideas and the recent **Log**

The page is static. The scheduled tasks run `build-snapshot.ps1` (which turns `focus.md` and the repo scan into two JSON documents) and write them to the page's database, so it updates live without being republished. Only repo names (last two path segments) and your board text are published, to your own account; setup asks before publishing anything.

## The `/focus` command

Setup installs `/focus` (from `commands/focus.md`) as your daily entry point:

- `/focus` or `/focus status` - where you are, what is open, what is idle
- `/focus start X, done when Y`
- `/focus park Z`
- `/focus switch to X`
- `/focus done`
- `/focus setup` - re-run the interview

It finds your board through a one-line pointer file at `~/.claude/focus-board-path`, written during setup.

You can also say the same things in plain chat.

## Files

```
.claude-plugin/
  plugin.json                     plugin manifest
  marketplace.json                marketplace manifest (rubenrups)
skills/focus-orchestrator/
  SKILL.md                        the skill (interview + build instructions)
  scan-repos.ps1                  read-only repo scanner
  build-snapshot.ps1              focus.md + repo scan -> dashboard JSON
  dashboard.html                  the dashboard page (published by setup, optional)
  commands/focus.md               the /focus slash command, installed by setup
README.md                         this file
.gitignore                        keeps personal state and secrets out of the repo
```

The scanner writes its report next to itself by default; setup always passes `-Out` so the report lands in your own focus folder, not the plugin cache.
