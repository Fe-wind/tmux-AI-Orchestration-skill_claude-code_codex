#!/bin/bash
# ask-codex-multi.sh - 複数のtmuxペインでCodexを同時に呼び出す
#
# 使用法:
#   ask-codex-multi.sh "質問"                    # ペイン1,2に同じ質問
#   ask-codex-multi.sh -p 1 "質問A" -p 2 "質問B" # 各ペインに異なる質問
#   ask-codex-multi.sh --setup                   # ペイン1,2を作成してCodex起動
#   ask-codex-multi.sh --send -p 1 "メッセージ"  # 既存Codexにメッセージ送信

set -e

SESSION=""
WINDOW=""
SETUP_MODE=false
SEND_MODE=false
SAME_PROMPT=""
declare -a PANE_PROMPTS=()
declare -a TARGET_PANES=()

usage() {
    echo "Usage: ask-codex-multi.sh [OPTIONS] [PROMPT]"
    echo ""
    echo "モード:"
    echo "  --setup              ペイン1,2を作成してCodexを起動"
    echo "  --send               既存のCodexにメッセージを送信"
    echo "  (デフォルト)          新規Codexを起動して質問"
    echo ""
    echo "Options:"
    echo "  -p, --pane NUM MSG   指定ペインに送るメッセージ（複数指定可）"
    echo "  -s, --session NAME   tmuxセッション名（現在のセッションがデフォルト）"
    echo "  -h, --help           このヘルプを表示"
    echo ""
    echo "例:"
    echo "  # ペイン1,2をセットアップ"
    echo "  ask-codex-multi.sh --setup"
    echo ""
    echo "  # 両ペインに同じ質問"
    echo "  ask-codex-multi.sh \"この関数を最適化して\""
    echo ""
    echo "  # 各ペインに異なる質問"
    echo "  ask-codex-multi.sh -p 1 \"反復で実装して\" -p 2 \"再帰で実装して\""
    echo ""
    echo "  # 既存Codexにメッセージ追加"
    echo "  ask-codex-multi.sh --send -p 1 \"別のアプローチで\""
    exit 0
}

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --setup)
            SETUP_MODE=true
            shift
            ;;
        --send)
            SEND_MODE=true
            shift
            ;;
        --pane|-p)
            TARGET_PANES+=("$2")
            PANE_PROMPTS+=("$3")
            shift 3
            ;;
        --session|-s)
            SESSION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            SAME_PROMPT="$1"
            shift
            ;;
    esac
done

# セッション自動検出
if [[ -z "$SESSION" ]]; then
    SESSION=$(tmux display-message -p '#S' 2>/dev/null) || {
        echo "Error: tmuxセッション内で実行してください" >&2
        exit 1
    }
fi

# ウィンドウ取得
WINDOW=$(tmux display-message -p '#I' 2>/dev/null || echo "0")

# ペイン数確認
PANE_COUNT=$(tmux list-panes -t "$SESSION:$WINDOW" 2>/dev/null | wc -l)

# === セットアップモード ===
if $SETUP_MODE; then
    echo "[Main] 複数ペインをセットアップします..."

    # 必要なペイン数を確保（最低3ペイン: 0=Main, 1=Codex-1, 2=Codex-2）
    if [[ "$PANE_COUNT" -lt 2 ]]; then
        echo "ペイン1を作成..."
        tmux split-window -h -t "$SESSION:$WINDOW.0"
        sleep 0.5
    fi

    PANE_COUNT=$(tmux list-panes -t "$SESSION:$WINDOW" 2>/dev/null | wc -l)
    if [[ "$PANE_COUNT" -lt 3 ]]; then
        echo "ペイン2を作成..."
        tmux split-window -v -t "$SESSION:$WINDOW.1"
        sleep 0.5
    fi

    # 各ペインでCodexを起動
    echo "ペイン1でCodex-1を起動..."
    tmux send-keys -t "$SESSION:$WINDOW.1" "codex --full-auto 'こんにちは、私はCodex-1です。ペイン1で動作しています。'"
    sleep 0.5
    tmux send-keys -t "$SESSION:$WINDOW.1" Enter

    echo "ペイン2でCodex-2を起動..."
    tmux send-keys -t "$SESSION:$WINDOW.2" "codex --full-auto 'こんにちは、私はCodex-2です。ペイン2で動作しています。'"
    sleep 0.5
    tmux send-keys -t "$SESSION:$WINDOW.2" Enter

    echo ""
    echo "[Main] セットアップ完了"
    echo "  ペイン0: Main (Claude/コーディネーター)"
    echo "  ペイン1: Codex-1"
    echo "  ペイン2: Codex-2"
    exit 0
fi

# === 送信モード（既存Codexにメッセージ送信）===
if $SEND_MODE; then
    if [[ ${#TARGET_PANES[@]} -eq 0 ]]; then
        echo "Error: --send モードでは -p でペインを指定してください" >&2
        exit 1
    fi

    echo "[Main] 既存Codexにメッセージを送信..."
    for i in "${!TARGET_PANES[@]}"; do
        pane="${TARGET_PANES[$i]}"
        msg="${PANE_PROMPTS[$i]}"
        echo "  ペイン$pane: $msg"
        tmux send-keys -t "$SESSION:$WINDOW.$pane" "$msg"
        sleep 0.5
        tmux send-keys -t "$SESSION:$WINDOW.$pane" Enter
    done

    echo "[Main] 送信完了"
    exit 0
fi

# === 通常モード（新規Codex起動して質問）===

# 同じ質問を複数ペインに送る場合
if [[ -n "$SAME_PROMPT" && ${#TARGET_PANES[@]} -eq 0 ]]; then
    TARGET_PANES=(1 2)
    PANE_PROMPTS=("$SAME_PROMPT" "$SAME_PROMPT")
fi

# ペイン指定がない場合はエラー
if [[ ${#TARGET_PANES[@]} -eq 0 ]]; then
    echo "Error: 質問内容を指定してください" >&2
    echo "Usage: ask-codex-multi.sh \"質問\" または ask-codex-multi.sh -p 1 \"質問A\" -p 2 \"質問B\"" >&2
    exit 1
fi

# 必要なペインを確保
MAX_PANE=0
for pane in "${TARGET_PANES[@]}"; do
    if [[ "$pane" -gt "$MAX_PANE" ]]; then
        MAX_PANE=$pane
    fi
done

while [[ "$PANE_COUNT" -le "$MAX_PANE" ]]; do
    echo "ペイン$PANE_COUNT を作成..."
    if [[ "$PANE_COUNT" -eq 1 ]]; then
        tmux split-window -h -t "$SESSION:$WINDOW.0"
    else
        tmux split-window -v -t "$SESSION:$WINDOW.1"
    fi
    sleep 0.5
    PANE_COUNT=$(tmux list-panes -t "$SESSION:$WINDOW" 2>/dev/null | wc -l)
done

# 各ペインでCodexを起動
echo "[Main] 複数ペインでCodexを起動..."
for i in "${!TARGET_PANES[@]}"; do
    pane="${TARGET_PANES[$i]}"
    prompt="${PANE_PROMPTS[$i]}"

    # エスケープ処理
    escaped_prompt=$(echo "$prompt" | sed "s/'/'\\\\''/g")

    echo "  ペイン$pane: $prompt"
    tmux send-keys -t "$SESSION:$WINDOW.$pane" "codex --full-auto '$escaped_prompt'"
    sleep 0.5
    tmux send-keys -t "$SESSION:$WINDOW.$pane" Enter
done

echo ""
echo "[Main] 起動完了。各ペインで応答を確認してください。"
