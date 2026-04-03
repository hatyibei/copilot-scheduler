# copilot-scheduler

GitHub Copilot CLI にスケジュール実行機能を追加する Agent Skill + Custom Agent。

Copilot が公式にはサポートしていない「指定時刻にタスクを自律実行する」機能を、
Agent Skills / Custom Agents / cron / GitHub Actions を組み合わせて実現する。

## 特徴

- **自然言語でスケジュール設定** — 「毎朝9時にテストを走らせて」と言うだけ
- **クロスプラットフォーム** — CLI / VS Code / Coding Agent すべてで動作
- **Markdown + Shell だけ** — VS Code 拡張不要、インストールは `.github/` にファイルを置くだけ
- **ローカル + リモート** — cron（ローカル）と GitHub Actions（リモート）の両方に対応
- **公式 API 準拠** — `copilot -p` のプログラマティックモードを使用、利用規約リスクなし

## セットアップ

### 1. リポジトリに配置

```bash
git clone https://github.com/yourname/copilot-scheduler.git
cd copilot-scheduler
```

または既存リポジトリに `.github/skills/schedule/` と `scripts/` をコピー。

### 2. Copilot CLI の確認

```bash
copilot --version    # v1.0.17+
copilot auth status  # 認証済みであること
```

## 使い方

### スキル経由（自然言語）

Copilot CLI のセッション内で、スケジュール関連のキーワードを含むプロンプトを入力すると
schedule スキルが自動的に発見・使用される:

```
> 毎朝9時にプロジェクトのTODOを整理して
> Schedule lint checks every weekday at 8am
> 5分おきにヘルスチェックして
```

### エージェント経由（対話的管理）

```bash
# 対話モード
copilot --agent scheduler

# 非対話モード
copilot --agent scheduler -p "スケジュール一覧を見せて"
copilot --agent scheduler -p "daily-lint を削除して"
```

### スクリプト直接実行

```bash
# 登録
bash scripts/register-local.sh \
  --cron "0 9 * * 1-5" \
  --prompt "Run all tests" \
  --name "daily-test" \
  --notify "log"

# 一覧
bash scripts/list-schedules.sh

# 削除
bash scripts/unregister-local.sh --name "daily-test"

# GitHub Actions ワークフロー生成
bash scripts/register-actions.sh \
  --cron "0 9 * * 1-5" \
  --prompt "Run all tests" \
  --name "daily-test" \
  --notify "issue"
```

## アーキテクチャ

```
User Input (自然言語)
    |
    v
+---------------------------+
| /schedule Skill (SKILL.md)|
| - 自然言語パース (LLM)    |
| - cron 式生成             |
| - 実行モード選択          |
+---------------------------+
    |
    +----------+-----------+
    |                      |
    v                      v
+-------------+  +------------------+
| Local Mode  |  | GitHub Actions   |
| crontab     |  | workflow YAML    |
| + copilot   |  | + copilot -p     |
|   -p PROMPT |  | + schedule cron  |
+------+------+  +--------+---------+
       |                   |
       v                   v
+-----------------------------+
| Result Notification         |
| log / GitHub Issue          |
+-----------------------------+
```

## ディレクトリ構成

```
copilot-scheduler/
├── .github/
│   ├── skills/schedule/SKILL.md    # スキル定義
│   └── agents/scheduler.agent.md   # カスタムエージェント
├── scripts/
│   ├── register-local.sh           # crontab 登録
│   ├── unregister-local.sh         # crontab 削除
│   ├── list-schedules.sh           # 一覧表示
│   ├── register-actions.sh         # GA workflow 生成
│   └── notify.sh                   # 結果通知
├── templates/
│   ├── cron-wrapper.sh.template    # ローカル実行テンプレート
│   └── actions-workflow.yml.template  # GA テンプレート
└── README.md
```

ランタイムデータは `~/.copilot-scheduler/` に格納:

```
~/.copilot-scheduler/
├── jobs/<name>/
│   ├── run.sh        # 生成された実行スクリプト
│   └── meta.json     # ジョブメタデータ
├── logs/             # 実行ログ (30日ローテーション)
└── locks/            # flock 用ロックファイル
```

## トラブルシューティング

### cron でジョブが動かない

cron は最小限の環境変数で実行されるため、`copilot` コマンドの PATH が通っていない可能性がある。
ラッパースクリプトが `PATH` を明示設定するので通常は問題ないが、以下で確認:

```bash
# ラッパーを直接実行して動作確認
bash ~/.copilot-scheduler/jobs/<name>/run.sh

# cron 環境をシミュレート
env -i HOME=$HOME bash ~/.copilot-scheduler/jobs/<name>/run.sh
```

### 認証エラー（`TypeError: fetch failed`）

プロキシ環境の場合、cron が `HTTP_PROXY` 等を持たないためネットワークに到達できない。
`register-local.sh` は登録時のプロキシ設定を自動でラッパーに埋め込むが、
プロキシ設定が変わった場合はジョブを再登録する:

```bash
bash scripts/unregister-local.sh --name "<name>"
bash scripts/register-local.sh --cron "..." --prompt "..." --name "<name>"
```

認証トークンが期限切れの場合:

```bash
copilot auth login
```

### ジョブが二重実行される

`flock` で防止しているが、ロックファイルが残っている場合:

```bash
rm ~/.copilot-scheduler/locks/<name>.lock
```

## セキュリティ

- `--allow-all-tools` フラグにより、スケジュール実行時の Copilot はすべてのツールにアクセスできる
- 信頼できるプロンプトのみをスケジュールすること
- GitHub Actions モードでは `COPILOT_TOKEN` シークレットの適切な管理が必要
- ログファイルにはプロンプトと実行結果が含まれるため、機密情報に注意

## ライセンス

MIT
