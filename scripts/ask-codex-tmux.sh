#!/bin/bash
# ask-codex-tmux.sh - tmuxペインでCodexを呼び出すヘルパースクリプト
#
# 使用法:
#   ask-codex-tmux.sh "質問内容"              # 現在のセッションで自動実行
#   ask-codex-tmux.sh -p 2 "質問内容"         # ペイン2を使用
#   ask-codex-tmux.sh -f file.txt "レビューして"  # ファイル添付
#   ask-codex-tmux.sh --exec "質問内容"       # execモード（非インタラクティブ）
#   ask-codex-tmux.sh -s multagent "質問内容" # セッション指定

set -e

SESSION=""  # 空の場合は現在のセッションを自動検出
TARGET_PANE=""  # 空の場合は自動決定
WAIT_TIME=30
FILE_CONTENT=""
PROMPT=""
USE_EXEC=false  # デフォルトはインタラクティブモード

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --pane|-p)
            TARGET_PANE="$2"
            shift 2
            ;;
        --file|-f)
            if [[ -f "$2" ]]; then
                FILE_CONTENT=$(cat "$2")
            else
                echo "Error: File not found: $2" >&2
                exit 1
            fi
            shift 2
            ;;
        --wait|-w)
            WAIT_TIME="$2"
            shift 2
            ;;
        --session|-s)
            SESSION="$2"
            shift 2
            ;;
        --exec|-e)
            USE_EXEC=true
            shift
            ;;
        --help|-h)
            echo "Usage: ask-codex-tmux.sh [OPTIONS] \"質問内容\""
            echo ""
            echo "Options:"
            echo "  -p, --pane NUM     使用するペイン番号 (自動決定がデフォルト)"
            echo "  -f, --file FILE    添付するファイル"
            echo "  -w, --wait SEC     待機時間秒 (default: 30)"
            echo "  -s, --session NAME tmuxセッション名 (現在のセッションがデフォルト)"
            echo "  -e, --exec         execモード（非インタラクティブ、結果自動取得）"
            echo ""
            echo "動作:"
            echo "  - セッション未指定: 現在のtmuxセッションを使用"
            echo "  - 1ペインのみ: 自動で横分割して新しいペインを作成"
            echo "  - 複数ペイン: 指定ペインまたはペイン1を使用"
            echo ""
            echo "モード:"
            echo "  デフォルト: インタラクティブモード（tmuxで直接操作可能）"
            echo "  --exec:     非インタラクティブ（結果を自動取得）"
            exit 0
            ;;
        *)
            PROMPT="$1"
            shift
            ;;
    esac
done

if [[ -z "$PROMPT" ]]; then
    echo "Error: 質問内容を指定してください" >&2
    echo "Usage: ask-codex-tmux.sh [OPTIONS] \"質問内容\"" >&2
    exit 1
fi

# セッション自動検出
if [[ -z "$SESSION" ]]; then
    SESSION=$(tmux display-message -p '#S' 2>/dev/null) || {
        echo "Error: tmuxセッション内で実行してください" >&2
        exit 1
    }
fi

# セッション確認
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Error: tmuxセッション '$SESSION' が見つかりません" >&2
    exit 1
fi

# 現在のウィンドウを取得
WINDOW=$(tmux display-message -p '#I' 2>/dev/null || echo "0")

# ペイン数を確認
PANE_COUNT=$(tmux list-panes -t "$SESSION:$WINDOW" 2>/dev/null | wc -l)

# 1ペインの場合は自動で分割
if [[ "$PANE_COUNT" -eq 1 ]]; then
    echo "1ペインのみ検出。新しいペインを作成します..."
    tmux split-window -h -t "$SESSION:$WINDOW"
    sleep 0.5
    TARGET_PANE=1
    echo "ペイン1を作成しました。"
elif [[ -z "$TARGET_PANE" ]]; then
    # ペインが複数あり、TARGET_PANEが未指定の場合はペイン1を使用
    TARGET_PANE=1
fi

# ペインの状態確認
PANE_CMD=$(tmux list-panes -t "$SESSION:$WINDOW" -F '#{pane_index}|#{pane_current_command}' | grep "^${TARGET_PANE}|" | cut -d'|' -f2)
if [[ -n "$PANE_CMD" && "$PANE_CMD" != "bash" ]]; then
    echo "Warning: ペイン $TARGET_PANE は '$PANE_CMD' を実行中です" >&2
fi

# ファイル内容があればプロンプトに追加
if [[ -n "$FILE_CONTENT" ]]; then
    FULL_PROMPT="$PROMPT

\`\`\`
$FILE_CONTENT
\`\`\`"
else
    FULL_PROMPT="$PROMPT"
fi

# エスケープ処理（シングルクォートをエスケープ）
ESCAPED_PROMPT=$(echo "$FULL_PROMPT" | sed "s/'/'\\\\''/g")

if $USE_EXEC; then
    # === execモード（非インタラクティブ）===
    OUTPUT_FILE="/tmp/codex-tmux-$$-pane${TARGET_PANE}.txt"

    echo "=== Codex呼び出し (execモード) ==="
    echo "セッション: $SESSION"
    echo "ウィンドウ: $WINDOW"
    echo "ペイン: $TARGET_PANE"
    echo "出力ファイル: $OUTPUT_FILE"
    echo "待機時間: ${WAIT_TIME}秒"
    echo ""

    # ファイルに出力をリダイレクト（2ステップ方式：文字列送信→Enter）
    tmux send-keys -t "$SESSION:$WINDOW.$TARGET_PANE" "codex exec '$ESCAPED_PROMPT' --skip-git-repo-check -o '$OUTPUT_FILE' 2>&1 | tee -a '$OUTPUT_FILE.log'; echo '=== CODEX_DONE ===' >> '$OUTPUT_FILE.log'"
    sleep 0.5
    tmux send-keys -t "$SESSION:$WINDOW.$TARGET_PANE" Enter

    echo "Codexを起動しました。tmuxで進行状況を確認できます。"
    echo ""

    # 結果待機（完了シグナルを監視）
    echo "${WAIT_TIME}秒待機中..."
    for i in $(seq 1 $WAIT_TIME); do
        sleep 1
        if [[ -f "$OUTPUT_FILE.log" ]] && grep -q "CODEX_DONE" "$OUTPUT_FILE.log" 2>/dev/null; then
            echo "Codex完了を検出"
            break
        fi
    done

    # 結果取得
    echo ""
    echo "=== Codexの結果 ==="
    if [[ -f "$OUTPUT_FILE" ]]; then
        cat "$OUTPUT_FILE"
    else
        echo "結果ファイルがまだ生成されていません"
        echo "tmuxで進行状況を確認してください"
    fi

else
    # === インタラクティブモード（デフォルト）===
    echo "=== Codex呼び出し (インタラクティブモード) ==="
    echo "セッション: $SESSION"
    echo "ウィンドウ: $WINDOW"
    echo "ペイン: $TARGET_PANE"
    echo ""

    # 通常のcodexコマンドを実行（2ステップ方式：文字列送信→Enter）
    # --full-auto: 承認プロンプトなしで自動実行
    tmux send-keys -t "$SESSION:$WINDOW.$TARGET_PANE" "codex --full-auto '$ESCAPED_PROMPT'"
    sleep 0.5
    tmux send-keys -t "$SESSION:$WINDOW.$TARGET_PANE" Enter

    echo "Codexを起動しました。"
    echo ""
    echo "tmuxのペイン $TARGET_PANE で進行状況を確認してください。"
    echo "Codexとインタラクティブにやり取りできます。"
fi
