#!/usr/bin/env bash
#
# 把一份 Plan Mode 的計畫檔留存到專案內。
#
# 進入 Plan Mode 與結束 Plan Mode 時各跑一次：前者留下原始計畫，後者留下實際執行後的
# 版本，同名覆寫。計畫檔本身常落在對話工具的暫存區，session 結束就找不到了；留一份
# 在專案裡，之後才查得到「當初是照什麼計畫做的」。
#
# 留檔路徑：
#   <專案根>/docs/working-notes-skill/plans/<標題>.md
#
# 「專案根」由 wn-common.sh 解析（git 根目錄，或往上找 CLAUDE.md／AGENTS.md 這類標記），
# **不是目前工作目錄**——工作目錄常常開在專案的上一層，照相對路徑寫會把檔案落在 repo 外。
#
# 檔名規則：
#   取計畫的 H1 標題（`# ` 開頭那行的第一個），中文字原樣保留，
#   空白與 / : ? * " < > | \ ( ) [ ] { } 及全形括號、引號、：？！、，。；｜
#   一律換成 -，連續的 - 收成一個，頭尾的 - 去掉，副檔名 .md。
#   沒有 H1 時退回用來源檔名。
#
#   例：`# 範例功能 v2 改版計畫（第二版）`
#       → <專案根>/docs/working-notes-skill/plans/範例功能-v2-改版計畫-第二版.md
#
# 執行：bash wn-plan.sh <計畫檔路徑>

set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/wn-common.sh"

SRC="${1:-}"
[ -n "$SRC" ] || wn_die '用法：wn-plan.sh <計畫檔路徑>'
[ -f "$SRC" ] || wn_die "找不到計畫檔：$SRC"

wn_resolve
wn_ensure_dir

mkdir -p "$WN_PLANS_DIR"

TITLE="$(LC_ALL=C sed -n 's/^# //p' "$SRC" | head -1)"
if [ -z "$TITLE" ]; then
    TITLE="$(basename "${SRC%.md}")"
    printf '⚠ 計畫檔沒有 H1 標題，改用檔名：%s\n' "$TITLE" >&2
fi

SLUG="$(wn_slug "$TITLE")"
[ -n "$SLUG" ] || wn_die "標題全是符號，算不出檔名：$TITLE"
DEST="$WN_PLANS_DIR/$SLUG.md"

# 同名覆寫是刻意的：同一個計畫在「開始」與「結束」各存一次，後者取代前者。
[ -f "$DEST" ] && printf 'ℹ️  同名計畫已存在，覆寫成這一版\n' >&2

cp "$SRC" "$DEST"
printf '%s\n' "$DEST"
