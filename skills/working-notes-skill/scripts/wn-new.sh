#!/usr/bin/env bash
#
# 建立一份新的施工筆記，檔名 YYYY-MM_NN_主題.md。
#
# NN 是「工作階段序號」不是日期：同一階段的多份筆記共用一個序號，開新階段才 +1。
# 順序資訊本身有價值，壓成日期反而把先後關係抹掉。
#
# 不自動重建索引——內容還沒寫，摘要抓不到東西。寫完再跑 wn-reindex.sh。
#
# 執行：bash <本檔所在目錄>/wn-new.sh "主題" [--new-stage]

set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/wn-common.sh"

TOPIC=""
NEW_STAGE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --new-stage) NEW_STAGE=1 ;;
        -*) wn_die "未知參數：$1" ;;
        *) [ -z "$TOPIC" ] && TOPIC="$1" || wn_die "只能給一個主題（含空白請加引號）" ;;
    esac
    shift
done

[ -n "$TOPIC" ] || wn_die '用法：wn-new.sh "主題" [--new-stage]'

wn_resolve
wn_ensure_dir

YM="$(date +%Y-%m)"

# 現有最大序號。tr + cut 逐位元組處理，不讓 awk 碰中文檔名。
MAX=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    if printf '%s' "$base" | LC_ALL=C grep -qE "$WN_NOTE_NAME_RE"; then
        n="$(printf '%s' "$base" | LC_ALL=C cut -d_ -f2)"
        n="$((10#$n))"
        [ "$n" -gt "$MAX" ] && MAX="$n"
    fi
done <<EOF
$(wn_note_files)
EOF

if [ "$MAX" -eq 0 ]; then
    STAGE=1
elif [ "$NEW_STAGE" -eq 1 ]; then
    STAGE="$((MAX + 1))"
else
    STAGE="$MAX"
fi

NN="$(printf '%02d' "$STAGE")"

# 檔名規則與 wn-plan.sh 共用 wn_slug（見 wn-common.sh）：
# 中文原樣保留，空白與檔案系統保留字元、全形括號標點換成 -，連續的收成一個。
SLUG="$(wn_slug "$TOPIC")"
[ -n "$SLUG" ] || wn_die "主題全是符號，算不出檔名：$TOPIC"

FILE="$WN_NOTES_DIR/${YM}_${NN}_${SLUG}.md"
[ -e "$FILE" ] && wn_die "已存在：$FILE"

TEMPLATE="$(cd "$(dirname "$0")/../assets" && pwd)/note-template.md"
[ -f "$TEMPLATE" ] || wn_die "找不到範本：$TEMPLATE"

# 標題用原始主題（保留空白與符號），檔名才是 slug 版本。
# 以佔位字串為界切成前後兩段，中間直接印主題，主題不經過任何取代語法：
# sed 會被 | & \ 的分隔符與跳脫絆到，${var/樣式/$主題} 在 bash 5.2 以上會把主題裡的 & 展開成樣式本身。
TEMPLATE_BODY="$(cat "$TEMPLATE")"
PLACEHOLDER='{{TITLE}}'
case "$TEMPLATE_BODY" in
    *"$PLACEHOLDER"*)
        printf '%s%s%s\n' "${TEMPLATE_BODY%%"$PLACEHOLDER"*}" "$TOPIC" "${TEMPLATE_BODY#*"$PLACEHOLDER"}" > "$FILE"
        ;;
    *) printf '%s\n' "$TEMPLATE_BODY" > "$FILE" ;;
esac

printf '%s\n' "$FILE"
printf '\n階段序號 %s（%s）。寫完內容後跑 wn-reindex.sh 重建索引。\n' \
    "$NN" "$([ "$NEW_STAGE" -eq 1 ] && printf '新階段' || printf '沿用目前階段')" >&2

# 專案有 ADR 就提醒：ADR 多半進版控、團隊看得到，決策理由該寫在那裡，筆記只寫一句指向它。
ADR_DIRS="$(wn_adr_dirs)"
if [ -n "$ADR_DIRS" ]; then
    {
        printf '\n這個專案有 ADR，決策以 ADR 為準：\n'
        printf '%s\n' "$ADR_DIRS" | while IFS= read -r d; do printf '  %s\n' "$d"; done
        printf '這次的決策若該寫 ADR（難以反悔、沒脈絡會意外、真的有取捨），理由寫進 ADR，筆記只寫一句指向它。\n'
    } >&2
fi
