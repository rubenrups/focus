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
4. **Local code** - do NOT assume a tidy folder. Run discovery first (see "Discovering the user's code" below), show what you found, and let the user confirm which locations to scan. Offer the repo scanner.
5. **Intensity** - quiet (digest + recap), moderate (+ idle/overload nudges), pushy (+ hourly check-ins).
6. **Work hours and days** - and how flexible (late starts/finishes). Shift windows ~30 min to fit.
7. **Notification channel** - push notification (PushNotification tool) or in-session only.

Write the understanding back as a short note and get correction before building.

## Discovering the user's code

Users keep code in all kinds of places: Desktop, Documents, Downloads, OneDrive, a second drive, WSL, one big folder, or scattered one-offs. Never hardcode a root. Do this, read-only:

1. **Check the usual suspects** that exist: home folder, Desktop, Documents, Downloads, OneDrive*, and folders named like `code`, `dev`, `src`, `source`, `repos`, `projects`, `work`, `git`, `workspace` on every drive. Also check the recent-projects lists of their editors if present (VS Code `storage.json`, JetBrains `recentProjects.xml`) and this app's session working directories (`list_sessions`).
2. **Find `.git` folders** under those places, depth <= 4, skipping `node_modules`, `vendor`, `.venv`, `AppData`, `Windows`, `Program Files`. Cap the effort: if it is slow, narrow to the folders the user names.
3. **Cluster by parent folder** and present a short table: folder | repo count | most recent commit. Do not list every repo.
4. **Ask** which clusters to scan, whether to add loose repos by path, and what to exclude (copies, backups, vendored clones, archived projects). Offer "scan everything found" as the recommended default only if the count is small (< 30); otherwise suggest only repos with a commit in the last 90 days.
5. **Persist the answer** as arguments in the scheduled-task prompts: `-Roots`, `-Repos`, `-Depth`, `-Exclude`. Tell the user how to add a new location later (edit the task prompt, or re-run this skill).

If no git repos are found, say so, drop the repo scanner from the setup, and continue with the other sources.

## 2. Build

Create under a folder the user picks (suggest `~/focus`, or next to their code if they prefer; never assume a path exists):

- `focus.md` - sections: Now (one task + done-when), Open (task | source | started | last touched), Parked, Log (append-only).
- `scan-repos.ps1` - copy from this skill's folder (next to this SKILL.md). It takes `-Roots`, `-Repos`, `-Depth`, `-Exclude`, `-Out`; pass the discovery answers. Run it once and show the summary to verify it works. On non-Windows, port to bash with the same output format.
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

Scheduled tasks only run while the app is open; tell the user a missed task runs on next launch.

## 4. Verify and hand over

- `list_scheduled_tasks` and show the final schedule.
- Offer to run the morning brief once as a test.
- Explain the chat commands: "start X, done when Y", "park: Z", "switch to X", "done".
- Offer (do not do unasked) a dashboard artifact as a later add-on.
