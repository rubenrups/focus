---
name: focus-orchestrator
description: Set up a personal focus orchestrator that keeps the user on task - state file, scheduled morning brief / hourly check-ins / end-of-day recap, and a read-only scan of local git repos for work that slips through. Use when the user wants to stay focused, track what they are working on across sessions, set up focus nudges, or recreate their focus setup on a new machine.
---

# Focus orchestrator setup

Interview the user, then generate a tailored setup. Never apply defaults silently: every choice below is asked, with a recommended default offered. Ask one question per message, multiple choice where possible. Reply in the user's language only if they ask; otherwise follow their global instructions.

Hard rules for everything this skill creates:
- Never commit, push, merge, or modify any repo. Repo scanning is read-only.
- Never write to external services (Trello, Gitea, etc.). Read-only.
- Never echo secrets; reference them by env file path and variable name.
- Before registering scheduled tasks, show the user the schedule table and get a yes.

## 1. Discover (interview)

Ask these, one at a time:

1. **Failure mode** - context-switching, stalling/forgetting, scope creep, or all. This decides which rules go into the check-in prompt (see step 3).
2. **Task sources** - any mix of: chat only, Trello (needs read-only key/token env file), Gitea/GitHub issues, other. Ask where credentials live; do not ask the user to paste secrets.
3. **Other sessions** - if `mcp__ccd_session_mgmt__list_sessions` is available, offer session activity as a source. If not available, skip.
4. **Local code** - do NOT assume a tidy folder and do NOT search on your own. Offer the repo scanner, then follow "Discovering the user's code" below: ask where the code lives and scan only the locations the user approves.
5. **Intensity** - quiet (digest + recap), moderate (+ idle/overload nudges), pushy (+ hourly check-ins).
6. **Work hours and days** - and how flexible (late starts/finishes). Shift windows ~30 min to fit.
7. **Notification channel** - push notification (PushNotification tool) or in-session only.

Write the understanding back as a short note and get correction before building.

## Discovering the user's code

Users keep code in all kinds of places: Desktop, Documents, Downloads, OneDrive, a second drive, WSL, one big folder, or scattered one-offs. Never hardcode a root. Do this, read-only:

**Consent first. Never search the machine on your own.** Do not look in any folder, drive, editor config or session list until the user has said which locations are allowed. Searching "everywhere" is not a default and not a fallback.

1. **Ask, don't look.** Ask the user where their code lives, in their own words: "Which folders hold the projects you want me to keep an eye on? You can name several, or individual repos." Accept paths, drive names or "none, skip this". If they are unsure, offer these as *suggestions to approve one by one*, without having checked whether they exist: a folder like `C:\Code`, `~/code`, `~/dev`, `~/Documents`, `~/Desktop`. Optionally offer to look at (a) their editor's recent-projects list or (b) this app's session working directories as a way to jog their memory, but only read them if they say yes to that specific source.
2. **Scan only approved paths.** For each approved folder, find `.git` directories up to the depth the user accepts (default 3, and say so), skipping `node_modules`, `vendor`, `.venv`, `AppData`, `Windows`, `Program Files`. Never descend outside an approved folder. Report any folder you could not read instead of working around it.
3. **Show before keeping.** Present a short table: folder | repo count | most recent commit. Ask which clusters to keep, whether to add loose repos by path, and what to exclude (copies, backups, vendored clones, archived projects). Suggest narrowing to repos with a commit in the last 90 days if the count is large (> 30).
4. **Persist the approved scope** as arguments in the scheduled-task prompts: `-Roots`, `-Repos`, `-Depth`, `-Exclude`. The scheduled runs must scan exactly that scope and nothing else; state this in each prompt. Tell the user how to widen or narrow it later (edit the task prompt, or re-run this skill).
5. **Reading repo contents.** The scanner only reads git metadata (status, branch, ahead count, last commit date). Do not read source files, `.env` files or secrets from scanned repos unless the user asks for a specific one.

If the user declines or no git repos are found, drop the repo scanner from the setup and continue with the other sources.

## 2. Build

Create under a folder the user picks (suggest `~/focus`, or next to their code if they prefer; never assume a path exists):

- `focus.md` - sections: Now (one task + done-when), Open (task | source | started | last touched), Parked, Log (append-only).
- `scan-repos.ps1` - copy from this skill's folder (next to this SKILL.md). It takes `-Roots`, `-Repos`, `-Depth`, `-Exclude`, `-Out`; pass the discovery answers. Run it once and show the summary to verify it works. On non-Windows, port to bash with the same output format.
- **`/focus` command** - copy `commands/focus.md` from this skill's folder to `~/.claude/commands/focus.md`, and write the absolute path of the user's `focus.md` as a single line into `~/.claude/focus-board-path`. Tell the user `/focus` is now their daily entry point (status, start, park, switch, done). Ask before overwriting an existing `focus.md` command.
- **Dashboard (optional, ask first)** - offer a persistent dashboard so the briefs can stay short. It is a private artifact page that shows Now, Open, Parked, Log and the repos needing attention. Explain that publishing sends the board and repo names (last two path segments only, no full paths, no file contents) to the user's own claude.ai account, and get a yes. If they agree: load the `artifact-design` and `artifact-capabilities` skills, copy `dashboard.html` from this skill's folder into the focus folder, publish it with `capabilities: {db: {}}`, store the URL in `dashboard-url.txt` next to the board, copy `build-snapshot.ps1` next to the board, run it, and seed `dash/board` and `dash/repos` with `ArtifactData` from the generated `snapshots/*.json`. The page is static; scheduled tasks only write those two documents, they never republish it. If they decline, skip every dashboard step below and keep the full text briefs.
- **Git tracking (optional, ask first)** - the board is plain text, so offer `git init` in the focus folder so it opens in the editor's diff view and keeps history. Add a `.gitignore` for `snapshots/` and `repo-scan.md`. Never commit, add a remote or push; the user does that. Warn that `focus.md` holds their task list and `dashboard-url.txt` a private link, so the folder should not be pushed anywhere public.
- Run the scan, then ask the user to eyeball the "needs attention" list for noise and add `-Exclude` patterns if they want.

## 3. Register scheduled tasks

Use `mcp__scheduled-tasks__create_scheduled_task` (load via ToolSearch if deferred). Prompts must be self-contained: each run has no memory of this chat. Include absolute paths to focus.md and the scanner, the source list, and the hard rules above. Cron is local time.

Generate only what the chosen intensity needs:

| Task | Quiet | Moderate | Pushy | Default time |
|---|---|---|---|---|
| morning brief | yes | yes | yes | work start + 15 min, weekdays |
| idle/overload check | no | 2-3x/day | hourly | inside work hours, off the hour |
| end-of-day recap | yes | yes | yes | work end + 30 min |

Task behaviour (adapt to the interview):
- **Morning brief**: scan repos; list sessions; read Trello (GET only); flag repos with uncommitted/unpushed work that have no card and no session ("slipping through"); refresh Open in focus.md; end with "What is the ONE thing today, and what is done-when?"; push notification.
- **Check-in**: stay silent if recent activity matches Now. Otherwise one message max: empty Now, working on something else (park or switch?), more than 3 open (drop or park?), Now idle 2h+. Only include the rules matching the user's failure mode.
- **Recap**: done today, Now vs done-when, carried over, uncommitted/unpushed work to decide on (list only; user commits), Parked review.
- **With a dashboard**: each task ends by running `build-snapshot.ps1` and writing the generated `board.json` / `repos.json` into the `dash` collection (read each document's `version` first and pass it as `if_version`). Briefs then print at most five lines plus the dashboard link. A silent check-in only `update`s `checkedAt` on `dash/board` and appends nothing to the Log, so the page does not look stale and the Log does not fill with "no change" lines. The morning brief passes its own "slipping through" judgement with `-Slipping 'Group\Name',...` (or `-Slipping '-'` for none).

Scheduled tasks only run while the app is open; tell the user a missed task runs on next launch.

## 4. Verify and hand over

- `list_scheduled_tasks` and show the final schedule.
- Offer to run the morning brief once as a test. Scheduled prompts that write to the dashboard are the part most likely to fail silently, so after that first run `list` the `dash` collection and confirm `board` and `repos` carry a fresh `updated` timestamp; report what you checked and what you could not.
- Explain the commands: `/focus`, `/focus start X, done when Y`, `/focus park Z`, `/focus switch to X`, `/focus done`.
- If the user declined the dashboard during build, mention once that it can be added later by re-running this skill; do not push it.
