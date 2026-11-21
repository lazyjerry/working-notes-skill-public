#!/bin/sh
#
# 從全域指令檔移除「施工筆記」規則段。
#
# 只拆掉標記區塊，區塊外的內容一個字不動。**不碰任何專案的筆記**——筆記在各專案的
# docs/ 底下，是使用者累積的施工紀錄，解除規則掛載不該順手清掉它們，所以沒有 --purge。
#
# 用法:
#   sh scripts/wn-uninstall.sh <目標路徑>
#     <目標路徑>：目錄（處理其下的 AGENTS.md／CLAUDE.md／GEMINI.md）或單一 .md 檔
#
# 目標路徑不給就列出偵測到的候選並結束——猜錯地方等於什麼都沒移除。
# 對沒安裝的狀態執行不報錯、不改檔（可重入）。

set -e

TARGET="${1:-}"
TS="$(date +%Y%m%d-%H%M%S)"

if [ -z "$TARGET" ]; then
    printf '用法: sh scripts/wn-uninstall.sh <目標路徑>\n\n' >&2
    printf '未指定目標。偵測到以下既有的 AI 指令檔：\n' >&2
    found=0
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" \
             "$HOME/.gemini/GEMINI.md" "$HOME/.ai-global/AGENTS.md"; do
        [ -f "$f" ] || continue
        printf '  %s\n' "$f" >&2
        found=1
    done
    [ "$found" -eq 0 ] && printf '  （沒有偵測到，請自行指定路徑）\n' >&2
    exit 1
fi

MARKER_BEGIN="<!-- BEGIN working-notes-skill:notes -->"
MARKER_END="<!-- END working-notes-skill:notes -->"

remove_file() {
    f="$1"

    if [ ! -f "$f" ]; then
        printf 'ℹ️  檔案不存在，已略過: %s\n' "$f"
        return 0
    fi

    if ! grep -qF "$MARKER_BEGIN" "$f"; then
        printf 'ℹ️  沒有施工筆記區塊，未改動: %s\n' "$f"
        return 0
    fi

    tmp="$f.wnremove.$$"
    trap 'rm -f "$tmp"' EXIT INT TERM

    # 只收掉區塊本身，外加安裝時多插的那一行空白，其餘一個字都不動。
    #
    # 空白行在哪邊要看區塊位置：插在檔頭時空行在區塊**後面**，插在中間或檔尾時
    # 在**前面**。兩種都要處理，否則反覆 install／uninstall 會一次多留一行。
    #
    # LC_ALL=C：檔案通篇中文，標記比對要走位元組語意。
    LC_ALL=C awk -v B="$MARKER_BEGIN" -v E="$MARKER_END" '
        index($0, B) > 0 {
            athead = (n == 0)
            if (!athead && buf[n-1] ~ /^[[:space:]]*$/) n--
            inblock = 1
            next
        }
        inblock {
            if (index($0, E) > 0) { inblock = 0; if (athead) skipblank = 1 }
            next
        }
        skipblank { skipblank = 0; if ($0 ~ /^[[:space:]]*$/) next }
        { buf[n++] = $0 }
        END { for (i = 0; i < n; i++) print buf[i] }
    ' "$f" > "$tmp"

    # 用 cat 寫回而不是 mv：目標是 symlink 時 mv 會把它換成實體檔，也會換掉原檔的權限。
    cp "$f" "$f.bak-$TS"
    cat "$tmp" > "$f"
    rm -f "$tmp"
    trap - EXIT INT TERM

    printf '✅ 已移除施工筆記區塊: %s（備份 .bak-%s）\n' "$f" "$TS"
}

if [ -d "$TARGET" ]; then
    remove_file "$TARGET/AGENTS.md"
    remove_file "$TARGET/CLAUDE.md"
    remove_file "$TARGET/GEMINI.md"
else
    case "$TARGET" in
        *.md) remove_file "$TARGET" ;;
        *) printf '❌ 目標必須是目錄或 .md 檔: %s\n' "$TARGET" >&2; exit 1 ;;
    esac
fi

printf '\n各專案 docs/working-notes-skill/ 底下的筆記原樣保留，本腳本不刪。\n'
