---
name: codex-tmux-wsl
description: WSL環境のtmuxマルチペインでCodexを呼び出してセカンドオピニオンを取得します。コードレビュー、実装アドバイス、バグ分析など、別のAIの視点が欲しい時に使用してください。
allowed-tools:
  - Bash
  - Read
  - Write
---

# Codex TMux WSL - セカンドオピニオン

WSL環境のtmuxでCodex CLIを呼び出し、セカンドオピニオンを取得するSkillです。

## 前提条件

- WSL環境で実行
- tmuxセッション内で実行
- Codex CLIがインストール済み

## 自動動作

スクリプトは環境を自動検出して適切に動作します：

| 状況 | 動作 |
|------|------|
| 1ペインのみ | 自動で横分割して新しいペインを作成 |
| 複数ペイン | 指定ペインまたはペイン1を使用 |
| セッション未指定 | 現在のtmuxセッションを使用 |

## 重要：tmux send-keysの2ステップ方式

tmuxでCodexにコマンドを送信する際は、**2ステップ方式**を使用すること：

```bash
# 1. 文字列を送信（Enterなし）
tmux send-keys -t "$SESSION:$WINDOW.$PANE" "コマンド文字列"
sleep 0.5
# 2. Enterを別途送信
tmux send-keys -t "$SESSION:$WINDOW.$PANE" Enter
```

**注意:** `tmux send-keys "文字列" Enter` の1行形式では正しく動作しない場合があります。

## ヘルパースクリプト

### 単一ペイン用: ask-codex-tmux.sh

```bash
# 基本（現在のセッションで自動実行、1ペインなら自動分割）
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh "質問内容"

# ペインを指定
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh -p 2 "質問内容"

# ファイルを添付
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh -f src/auth.ts "このコードをレビューして"

# execモード（非インタラクティブ、結果自動取得）
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh --exec "質問内容"

# セッションを指定（multagentセッションなど）
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh -s multagent "質問内容"

# 待機時間を指定（execモード用）
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh --exec -w 60 "複雑な質問"
```

### 複数ペイン用: ask-codex-multi.sh

複数のCodexインスタンスを同時に操作するためのスクリプトです。

```bash
# ペイン1,2をセットアップ（Codex起動まで自動実行）
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-multi.sh --setup

# 両ペインに同じ質問を送信
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-multi.sh "この関数を最適化して"

# 各ペインに異なる質問を送信
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-multi.sh -p 1 "反復で実装して" -p 2 "再帰で実装して"

# 既存のCodexにメッセージを追加送信
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-multi.sh --send -p 1 "別のアプローチで"
```

#### 複数ペインのモード

| モード | 説明 |
|--------|------|
| `--setup` | ペイン1,2を作成してCodexを起動 |
| `--send` | 既存のCodexにメッセージを送信 |
| (デフォルト) | 新規Codexを起動して質問 |

#### ペイン構成

```
┌─────────────────┬─────────────────┐
│                 │     Codex-1     │
│   Main (ペイン0)  │    (ペイン1)     │
│   Claude/       ├─────────────────┤
│   コーディネーター │     Codex-2     │
│                 │    (ペイン2)     │
└─────────────────┴─────────────────┘
```

- **ペイン0 (Main)**: Claude Codeがコーディネーターとして動作
- **ペイン1,2**: Codexインスタンスがワーカーとして動作
- Main が各ペインに指示を出し、結果を取りまとめる

### 単一ペイン用オプション一覧

| オプション | 説明 |
|-----------|------|
| `-p, --pane NUM` | 使用するペイン番号（自動決定がデフォルト） |
| `-f, --file FILE` | 添付するファイル |
| `-w, --wait SEC` | 待機時間秒（default: 30） |
| `-s, --session NAME` | tmuxセッション名（現在のセッションがデフォルト） |
| `-e, --exec` | execモード（非インタラクティブ） |

### モードの違い

| モード | コマンド | 特徴 |
|--------|----------|------|
| インタラクティブ | `codex --full-auto "プロンプト"` | tmuxで直接操作可能、会話継続可能、承認プロンプトなし |
| exec | `codex exec ...` | 非インタラクティブ、結果自動取得 |

**注意:** `--full-auto` オプションにより、Codexは承認プロンプトなしで自動実行されます。

## 使用例

### 1. シンプルな質問（1ペインから自動分割）

```bash
# 現在1ペインの場合、自動で分割してCodexを起動
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh "このコードの改善点を教えて"
```

### 2. 手動でペインを分割してCodex起動

```bash
# 現在のセッション情報を取得
SESSION=$(tmux display-message -p '#S')
WINDOW=$(tmux display-message -p '#I')

# ペインを横分割
tmux split-window -h -t "$SESSION:$WINDOW"
sleep 0.5

# 新しいペイン（ペイン1）でCodexを起動（2ステップ方式）
# --full-auto: 承認プロンプトなしで自動実行
tmux send-keys -t "$SESSION:$WINDOW.1" "codex --full-auto 'こんにちは'"
sleep 0.5
tmux send-keys -t "$SESSION:$WINDOW.1" Enter
```

### 3. インタラクティブな会話を続ける

```bash
# 追加のメッセージを送信（2ステップ方式）
SESSION=$(tmux display-message -p '#S')
WINDOW=$(tmux display-message -p '#I')

tmux send-keys -t "$SESSION:$WINDOW.1" "追加の質問です"
sleep 0.5
tmux send-keys -t "$SESSION:$WINDOW.1" Enter
```

### 4. multagentセッションで使用

```bash
# multagentセッションのペイン1（A01）を使用
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh -s multagent -p 1 "質問内容"
```

### 5. execモードで結果自動取得

```bash
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh --exec "このコードのバグを見つけて"
```

## 結果の報告

Codexからの回答を受け取ったら：

1. 回答を要約してユーザーに伝える
2. Claude（自分）の見解と比較する
3. 両者の意見が異なる場合は、その違いを説明する
4. 最終的な推奨事項を提示する

## トラブルシューティング

### tmuxセッション外で実行した場合

```
Error: tmuxセッション内で実行してください
```
→ tmuxセッション内でスクリプトを実行してください

### ペインがビジー

```bash
# Codexを終了
tmux send-keys -t "$SESSION:$WINDOW.1" C-c

# または別のペインを使用
~/.claude/skills/codex-tmux-wsl/scripts/ask-codex-tmux.sh -p 2 "質問"
```

### Codexがタイムアウト

- 質問を短くする
- 複雑なタスクは分割する
- `--exec`モードで`-w`オプションで待機時間を延長

## 注意事項

- ユーザーはtmuxで進行状況をリアルタイムに確認可能
- インタラクティブモードでは会話を継続可能
- 1ペインの場合は自動で分割される
- 長いファイルを送る場合はトークン制限に注意
