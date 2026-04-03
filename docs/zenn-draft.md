---
title: "Copilotにスケジュール実行機能を自作してみた ── Agent Skills × cron × GitHub Actions で定期タスク自動化"
emoji: "⏰"
type: "tech"
topics: ["githubcopilot", "cli", "cron", "githubactions", "automation"]
published: false
---

# はじめに：Copilot CLI にはスケジュール機能がない

GitHub Copilot CLI は `copilot -p "プロンプト"` でプログラマティックに実行できる。
しかし「毎朝9時にこれを実行して」と言っても、Copilot は時計を持っていない。

実際に [Feature Request #1662](https://github.com/github/copilot-cli/issues/1662) でスケジュール実行の要望が出ているが、公式にはまだ対応されていない。

**ならば、既存の拡張ポイントで自作しよう。**

本記事では、Agent Skills / Custom Agents / cron / GitHub Actions を組み合わせて、
Copilot CLI にスケジュール実行機能を追加する方法を解説する。

## 既存アプローチとの差別化

| 方式 | 環境 | 特徴 |
|------|------|------|
| [Copilot Scheduler (VS Code拡張)](https://marketplace.visualstudio.com/items?itemName=yamapan.copilot-scheduler) | VS Code のみ | WebView GUI、cron式対応。Chat API自動操作のため利用規約リスクあり |
| GitHub Actions + `copilot -p` | CI/CD | 公式ドキュメント記載。YAML手書きが必要 |
| **本プロジェクト (Agent Skills)** | **CLI / VS Code / Coding Agent** | **Markdown + Shell のみ。公式プログラマティックモード使用** |

本プロジェクトのポイント:
- **VS Code 拡張を書かない** — Markdown と Shell スクリプトだけで実現
- **クロスプラットフォーム** — 同じ SKILL.md が CLI でも VS Code でも動く
- **公式 API 準拠** — `copilot -p` のプログラマティックモードを使用

---

# 設計方針：なぜ Agent Skills で作るのか

## Copilot の拡張ポイント

Copilot CLI には3つの拡張ポイントがある:

| 拡張ポイント | 用途 | 配置場所 |
|------------|------|---------|
| **Agent Skills** | 特定タスクの知識と手順を提供 | `.github/skills/<name>/SKILL.md` |
| **Custom Agents** | 対話的なワークフロー | `.github/agents/<name>.agent.md` |
| **Hooks** | セッションイベントへの反応 | `.github/hooks/` |

これらは全てテキストファイルベースで、特別なランタイムや拡張フレームワークが不要。

## 自然言語パースを LLM に委譲する設計

最大の設計判断は **「自然言語のパースを LLM 自身にやらせる」** こと。

従来のアプローチ:
```
ユーザー入力 → 正規表現/NLPでパース → 構造化データ → コマンド実行
```

本プロジェクトのアプローチ:
```
ユーザー入力 → SKILL.md の指示に従って LLM が解析 → シェルコマンド生成 → 実行
```

SKILL.md に「ユーザーの入力から what/when/where を抽出し、when を cron 式に変換せよ」と
書くだけで、Copilot が自力で解釈する。パーサーを書く必要がない。

---

# 実装：schedule スキルを作る

## SKILL.md の構造

```yaml
---
name: schedule
description: >-
  Schedule recurring Copilot tasks using cron or GitHub Actions.
  Use when: schedule, スケジュール, 定期実行, cron, 毎日, 毎週, ...
user-invocable: true
---
```

`description` に含まれるキーワードが、スキルの自動発見に使われる。
「スケジュール」「毎日」「cron」などの単語を含めておくと、ユーザーがこれらの言葉を使った時に
スキルが自動的に選択される。

## cron 式変換テーブル

SKILL.md の本文に変換テーブルを記載する:

| 自然言語 | cron 式 |
|---------|---------|
| 毎日9時 | `0 9 * * *` |
| 平日18時 | `0 18 * * 1-5` |
| 5分おき | `*/5 * * * *` |
| 毎週月曜10時 | `0 10 * * 1` |

LLM はこのテーブルを参考に、任意の自然言語表現を cron 式に変換する。

## スクリプト群

スキルが呼び出すシェルスクリプト:

- `register-local.sh` — crontab にジョブを登録
- `list-schedules.sh` — 登録済みジョブの一覧表示
- `unregister-local.sh` — ジョブの削除
- `notify.sh` — 実行結果の通知（GitHub Issue など）

---

# デモ：実際に動かしてみる

## ローカル cron 登録

```bash
$ copilot -p "毎朝9時にこのプロジェクトのテストを走らせて結果をログに残して"
```

Copilot が schedule スキルを発見し、以下を実行:

```
Schedule to register:
  Name:     daily-test
  Schedule: 0 9 * * * (毎日午前9時)
  Task:     Run all tests and save results
  Mode:     local (crontab)
  Notify:   log

Proceed? (y/n)
```

承認すると、`crontab` にエントリが追加される:

```
# copilot-scheduler:daily-test
0 9 * * * /home/user/.copilot-scheduler/jobs/daily-test/run.sh
```

## 管理はエージェント経由で

```bash
$ copilot --agent scheduler
> スケジュール一覧を見せて

NAME                 CRON               NOTIFY   PROMPT
----                 ----               ------   ------
daily-test           0 9 * * *          log      Run all tests and save results

Total: 1 task(s)

> daily-test を削除して

Removed: daily-test
```

---

# cron 環境での罠

cron ジョブの実行環境は最小限で、通常のシェルとは異なる。

## 罠1: PATH が通らない

cron は `/usr/bin:/bin` 程度の PATH しか持たない。
nvm でインストールした `copilot` コマンドは見つからない。

**解決策**: ラッパースクリプトで絶対パスと PATH を明示設定:

```bash
export PATH="/home/user/.nvm/versions/node/v18.20.8/bin:/usr/local/bin:/usr/bin:/bin"
COPILOT="/home/user/.nvm/versions/node/v18.20.8/bin/copilot"
"$COPILOT" -p "$PROMPT" --allow-all-tools --no-ask-user
```

## 罠2: 二重実行

Copilot の応答に時間がかかると、次の cron 実行がオーバーラップする可能性がある。

**解決策**: `flock` でプロセスロック:

```bash
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Already running. Skipping."
  exit 0
fi
```

## 罠3: 認証切れ

Copilot CLI の認証トークンには有効期限がある。
cron ジョブが深夜に実行される場合、認証が切れている可能性がある。

**解決策**: ログを確認して手動で `copilot auth login` を実行。
（自動更新の仕組みは今後の課題）

---

# GitHub Actions 展開

ローカル cron に加え、GitHub Actions の `schedule` トリガーでも実行できる:

```bash
$ bash scripts/register-actions.sh \
    --cron "0 2 * * *" \
    --prompt "Analyze open issues and create a summary" \
    --name "nightly-issue-summary" \
    --notify "issue"
```

これで `.github/workflows/copilot-sched-nightly-issue-summary.yml` が生成される。

---

# カスタムエージェントで管理 UI

`.github/agents/scheduler.agent.md` を配置すると、
`copilot --agent scheduler` で対話的なスケジュール管理ができる。

エージェントは5つの操作を理解する:
1. 新規登録
2. 一覧表示
3. 削除
4. 履歴確認
5. テスト実行

---

# VS Code からも使えるよ

Agent Skills は [オープン仕様](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) で、
`.github/skills/` に置けば VS Code の Agent Mode からも認識される。

つまり、**同じ SKILL.md が CLI でも VS Code でも Coding Agent でも動く**。

VS Code 拡張の Copilot Scheduler (yamapan) は VS Code 専用だが、
本プロジェクトはプラットフォームを選ばない。

---

# まとめ：Copilot の拡張ポイントは想像以上に柔軟

Feature Request #1662 は「公式でスケジュール機能を実装してほしい」という要望だが、
既存の拡張ポイント（Skills / Agents / Hooks）を組み合わせれば、自分で作れてしまう。

ポイント:
- **SKILL.md はパーサー不要** — 自然言語の解析は LLM に委譲できる
- **Shell スクリプトとの連携が強力** — crontab 操作も GitHub CLI 操作もシンプルに書ける
- **クロスプラットフォーム** — テキストファイルベースだから、どこでも動く

Copilot CLI の `copilot -p` + `--allow-all-tools` + `--no-ask-user` は、
実質的に「自律エージェントのプログラマティック実行」を可能にするフラグ。
これに cron を組み合わせるだけで、夜間自律開発の第一歩が踏み出せる。

公式が #1662 を実装する前に、自分で作ってしまおう。

---

## リポジトリ

https://github.com/yourname/copilot-scheduler

## 参考リンク

- [Copilot CLI - Creating agent skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills)
- [Copilot CLI - Creating custom agents](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents)
- [Feature Request #1662](https://github.com/github/copilot-cli/issues/1662)
- [Copilot Scheduler (VS Code 拡張)](https://marketplace.visualstudio.com/items?itemName=yamapan.copilot-scheduler)
