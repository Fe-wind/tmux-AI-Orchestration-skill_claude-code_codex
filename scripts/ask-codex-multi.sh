#!/bin/bash
# ask-codex-multi.sh - 複数のtmuxペインでCodexを同時に呼び出す
#
# 使用法:
#   ask-codex-multi.sh "質問"                       # ペイン1..(N-1)に同じ質問 (default: total 3)
#   ask-codex-multi.sh -n 4 "質問"                  # ペイン1..3に同じ質問 (ペイン0を含む合計4)
#   ask-codex-multi.sh -p 1 "質問A" -p 2 "質問B"    # 各ペインに異なる質問
#   ask-codex-multi.sh --setup                     # ペイン0..(N-1)を作成してCodex起動 (default: total 3)
#   ask-codex-multi.sh --setup -n 4                # ペイン0..3を作成してCodex起動
#   ask-codex-multi.sh --workers 4 --setup         # ワーカーペイン数を指定してセットアップ
#   ask-codex-multi.sh --send -p 1 "メッセージ"     # 既存Codexにメッセージ送信

set -e

SESSION=""
WINDOW=""
SETUP_MODE=false
SEND_MODE=false
SAME_PROMPT=""
REQUESTED_TOTAL_PANES=""
REQUESTED_WORKERS=""
declare -a PANE_PROMPTS=()
declare -a TARGET_PANES=()

usage() {
    echo "Usage: ask-codex-multi.sh [OPTIONS] [PROMPT]"
    echo ""
    echo "モード:"
    echo "  --setup              ペイン0..(N-1)を作成してCodexを起動 (default: total 3)"
    echo "  --send               既存のCodexにメッセージを送信"
    echo "  (デフォルト)          新規Codexを起動して質問"
    echo ""
    echo "Options:"
    echo "  -p, --pane NUM MSG   指定ペインに送るメッセージ（複数指定可）"
    echo "  -n, --panes NUM      ペイン0を含む合計ペイン数 (default: 3)"
    echo "      --workers NUM    ワーカーペイン数（ペイン1..）を指定"
    echo "  -s, --session NAME   tmuxセッション名（現在のセッションがデフォルト）"
    echo "  -h, --help           このヘルプを表示"
    echo ""
    echo "例:"
    echo "  # ペイン0..2をセットアップ"
    echo "  ask-codex-multi.sh --setup"
    echo ""
    echo "  # ペイン0..3をセットアップ"
    echo "  ask-codex-multi.sh --setup -n 4"
    echo ""
    echo "  # 複数ペインに同じ質問"
    echo "  ask-codex-multi.sh -n 3 \"この関数を最適化して\""
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
        --panes|-n)
            REQUESTED_TOTAL_PANES="$2"
            shift 2
            ;;
        --workers)
            REQUESTED_WORKERS="$2"
            shift 2
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

if [[ -n "$REQUESTED_TOTAL_PANES" && -n "$REQUESTED_WORKERS" ]]; then
    echo "Error: --panes と --workers は同時に指定できません" >&2
    exit 1
fi

if [[ -n "$REQUESTED_TOTAL_PANES" ]]; then
    if ! [[ "$REQUESTED_TOTAL_PANES" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --panes は2以上の整数を指定してください" >&2
        exit 1
    fi
    if [[ "$REQUESTED_TOTAL_PANES" -lt 2 ]]; then
        echo "Error: --panes は2以上の整数を指定してください" >&2
        exit 1
    fi
fi

if [[ -n "$REQUESTED_WORKERS" ]]; then
    if ! [[ "$REQUESTED_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --workers は1以上の整数を指定してください" >&2
        exit 1
    fi
fi

resolve_worker_count() {
    local workers
    if [[ -n "$REQUESTED_TOTAL_PANES" ]]; then
        workers=$((REQUESTED_TOTAL_PANES - 1))
    elif [[ -n "$REQUESTED_WORKERS" ]]; then
        workers="$REQUESTED_WORKERS"
    else
        workers=2
    fi
    echo "$workers"
}

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
    WORKER_COUNT=$(resolve_worker_count)
    TOTAL_PANES=$((WORKER_COUNT + 1))

    echo "[Main] 複数ペインをセットアップします... (panes=${TOTAL_PANES}, workers=${WORKER_COUNT})"
    while [[ "$PANE_COUNT" -lt "$TOTAL_PANES" ]]; do
        echo "ペイン$PANE_COUNT を作成..."
        if [[ "$PANE_COUNT" -eq 1 ]]; then
            tmux split-window -h -t "$SESSION:$WINDOW.0"
        else
            tmux split-window -v -t "$SESSION:$WINDOW.1"
        fi
        sleep 0.5
        PANE_COUNT=$(tmux list-panes -t "$SESSION:$WINDOW" 2>/dev/null | wc -l)
    done

    tmux select-layout -t "$SESSION:$WINDOW" tiled >/dev/null 2>&1 || true

    for pane in $(seq 1 "$WORKER_COUNT"); do
        echo "ペイン${pane}でCodex-${pane}を起動..."
        tmux send-keys -t "$SESSION:$WINDOW.$pane" "codex --dangerously-bypass-approvals-and-sandbox 'こんにちは、私はCodex-${pane}です。ペイン${pane}で動作しています。'"
        sleep 0.5
        tmux send-keys -t "$SESSION:$WINDOW.$pane" Enter
    done

    echo ""
    echo "[Main] セットアップ完了"
    echo "  ペイン0: Main (Codex/コーディネーター)"
    for pane in $(seq 1 "$WORKER_COUNT"); do
        echo "  ペイン${pane}: Codex-${pane}"
    done
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
    WORKER_COUNT=$(resolve_worker_count)
    for pane in $(seq 1 "$WORKER_COUNT"); do
        TARGET_PANES+=("$pane")
        PANE_PROMPTS+=("$SAME_PROMPT")
    done
fi

# ペイン指定がない場合はエラー
if [[ ${#TARGET_PANES[@]} -eq 0 ]]; then
    echo "Error: 質問内容を指定してください" >&2
    echo "Usage: ask-codex-multi.sh -n 3 \"質問\" または ask-codex-multi.sh -p 1 \"質問A\" -p 2 \"質問B\"" >&2
    exit 1
fi

for pane in "${TARGET_PANES[@]}"; do
    if [[ "$pane" == "0" ]]; then
        echo "Error: ペイン0はMain用のため指定できません。1以上のペインを指定してください。" >&2
        exit 1
    fi
done

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
    tmux send-keys -t "$SESSION:$WINDOW.$pane" "codex --dangerously-bypass-approvals-and-sandbox '$escaped_prompt'"
    sleep 0.5
    tmux send-keys -t "$SESSION:$WINDOW.$pane" Enter
done

echo ""
echo "[Main] 起動完了。各ペインで応答を確認してください。"
