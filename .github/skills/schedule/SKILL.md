---
name: schedule
description: >-
  Schedule recurring Copilot tasks using cron or GitHub Actions.
  Use when: schedule, スケジュール, 定期実行, cron, 毎日, 毎週, 毎月,
  recurring, periodic, timer, overnight, 夜間バッチ, 自動実行,
  タイマー, 定時, 予約実行
user-invocable: true
---

# Copilot Scheduler Skill

Schedule recurring tasks that Copilot executes automatically via cron (local) or GitHub Actions (remote).

## How to Use

The user will describe a task to schedule in natural language, such as:
- "毎朝9時にテストを走らせて"
- "Schedule a lint check every weekday at 8am"
- "5分おきにヘルスチェックして"
- "スケジュール一覧を見せて"
- "daily-lint を削除して"

## Step 1: Determine the User's Intent

Classify the request into one of these operations:

| Intent | Action |
|--------|--------|
| Register a new schedule | Go to Step 2 |
| List existing schedules | Run `bash {{projectRoot}}/scripts/list-schedules.sh` and show the result |
| Delete a schedule | Run `bash {{projectRoot}}/scripts/unregister-local.sh --name "<name>"` |
| Show execution history | Read log files from `~/.copilot-scheduler/logs/` for the specified task |
| Test-run a schedule now | Run `bash ~/.copilot-scheduler/jobs/<name>/run.sh` directly |

If the intent is not "register", execute the corresponding action and stop.

## Step 2: Extract Schedule Parameters

Parse the user's natural language input to extract these 4 parameters:

### WHAT (required)
The task/prompt that Copilot should execute. This is what will be passed to `copilot -p`.

### WHEN (required)
Convert the time expression to a **cron 5-field expression** (`minute hour day-of-month month day-of-week`).

Common conversion patterns:

| Natural Language | Cron Expression |
|-----------------|----------------|
| 毎日N時 / every day at N | `0 N * * *` |
| 平日N時 / weekdays at N | `0 N * * 1-5` |
| 毎週月曜N時 / every Monday at N | `0 N * * 1` |
| 毎週月水金N時 | `0 N * * 1,3,5` |
| N分ごと / every N minutes | `*/N * * * *` |
| N時間ごと / every N hours | `0 */N * * *` |
| 毎月1日N時 / 1st of every month at N | `0 N 1 * *` |
| 毎日N時M分 / daily at N:M | `M N * * *` |

Day of week: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat

### WHERE (optional, default: `local`)
- `local` — Register as a crontab entry on the local machine
- `actions` — Generate a GitHub Actions workflow file (Phase 2)

### NOTIFY (optional, default: `log`)
- `log` — Save output to log file only
- `issue` — Create a GitHub Issue with the result
- `none` — No notification

### NAME (auto-generated)
Generate a short, descriptive kebab-case name from the task description.
Examples: `daily-lint`, `weekly-test`, `hourly-healthcheck`

## Step 3: Confirm with the User

Before registering, display a confirmation summary:

```
Schedule to register:
  Name:     <NAME>
  Schedule: <CRON> (<human-readable description>)
  Task:     <WHAT>
  Mode:     <WHERE>
  Notify:   <NOTIFY>

Proceed? (y/n)
```

Wait for the user to confirm before proceeding.

## Step 4: Register the Schedule

### Local Mode (cron)

Run the following command:

```bash
bash {{projectRoot}}/scripts/register-local.sh \
  --cron "<CRON>" \
  --prompt "<WHAT>" \
  --name "<NAME>" \
  --notify "<NOTIFY>" \
  --working-dir "<current working directory>"
```

Replace `{{projectRoot}}` with the absolute path to the copilot-schedule project directory.

### Actions Mode (GitHub Actions)

Run the following command:

```bash
bash {{projectRoot}}/scripts/register-actions.sh \
  --cron "<CRON>" \
  --prompt "<WHAT>" \
  --name "<NAME>" \
  --notify "<NOTIFY>"
```

## Step 5: Verify Registration

After registration, run:

```bash
bash {{projectRoot}}/scripts/list-schedules.sh
```

Show the result to confirm the task was registered successfully.

## Important Notes

- Cron jobs run with minimal environment variables. The wrapper script handles PATH and Node.js setup automatically.
- Use `flock` for double-run prevention — if a previous execution is still running, the next one is skipped.
- Logs are stored in `~/.copilot-scheduler/logs/` and auto-rotated after 30 days.
- The `copilot` CLI must be authenticated. If auth expires, the cron job will fail with an error in the log.

## Troubleshooting

If asked about issues:
1. Check logs: `ls -lt ~/.copilot-scheduler/logs/ | head`
2. Check crontab: `crontab -l | grep copilot-scheduler`
3. Test manually: `bash ~/.copilot-scheduler/jobs/<name>/run.sh`
4. Check auth: `copilot auth status` (if available)
