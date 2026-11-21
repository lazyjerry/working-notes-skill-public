#!/usr/bin/env bash
#
# 把一份筆記標成過時（或取消），並重建索引。
#
# 標記是 H1 下方第一個非空行的 `> 過時：<以此為準>`。過時筆記不刪：當時的脈絡還有
# 參考價值，但不該再出現在動工前要掃的 index.md 裡，所以 wn-reindex.sh 會把它移到
# obsolete.md。「以此為準」寫現在該看哪裡——取代它的規範檔或筆記。
#
# 已經有標記就改寫原因，不會疊兩行；--clear 拿掉標記，筆記回到標記前的樣子。
# 做完自動重建索引：標過時的當下內容已經定了，不像 wn-new.sh 建檔時還是空的。
#
# 執行：bash <本檔所在目錄>/wn-obsolete.sh 2026-08_02_註解撰寫要求.md "條款已併入 docs/CONTRIBUTING.md 的「註解」"
#       bash <本檔所在目錄>/wn-obsolete.sh --clear 2026-08_02_註解撰寫要求.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/wn-common.sh"

USAGE='用法：wn-obsolete.sh <筆記> "<以此為準>"｜wn-obsolete.sh --clear <筆記>'

CLEAR=0
NOTE_ARG=""
REASON=""
ARGC=0

while [ $# -gt 0 ]; do
    case "$1" in
        --clear) CLEAR=1 ;;
        -*) wn_die "未知參數：$1" ;;
        *)
            ARGC="$((ARGC + 1))"
            case "$ARGC" in
                1) NOTE_ARG="$1" ;;
                2) REASON="$1" ;;
                *) wn_die "參數太多（原因含空白請加引號）。$USAGE" ;;
            esac
            ;;
    esac
    shift
done

[ -n "$NOTE_ARG" ] || wn_die "$USAGE"

if [ "$CLEAR" -eq 1 ]; then
    [ -z "$REASON" ] || wn_die "--clear 不帶原因。$USAGE"
else
    # 原因會變成索引表格的一格，也是標記那一行本身：換行會把兩邊都拆壞。
    case "$REASON" in
        *$'\n'* | *$'\r'*) wn_die "原因只能有一行" ;;
    esac
    trimmed="${REASON//[[:space:]]/}"
    [ -n "$trimmed" ] || wn_die "要寫明以哪裡為準，原因不能是空的。$USAGE"
fi

wn_resolve
wn_has_notes || wn_die "這個專案還沒有施工筆記（$WN_NOTES_DIR 不存在）"

# 只給檔名就到筆記目錄找；給路徑就照路徑，但實體位置必須就在筆記目錄底下。
case "$NOTE_ARG" in
    */*) NOTE="$NOTE_ARG" ;;
    *) NOTE="$WN_NOTES_DIR/$NOTE_ARG" ;;
esac
[ -f "$NOTE" ] || wn_die "找不到筆記：$NOTE"

NOTE_DIR="$(cd "$(dirname "$NOTE")" && pwd -P)"
NOTES_DIR_REAL="$(cd "$WN_NOTES_DIR" && pwd -P)"
[ "$NOTE_DIR" = "$NOTES_DIR_REAL" ] || wn_die "只能標 $WN_NOTES_DIR 底下的筆記：$NOTE"

BASE="$(basename "$NOTE")"
case "$BASE" in
    index.md | "$WN_OBSOLETE_INDEX") wn_die "索引檔不是筆記：$BASE" ;;
    *.md) ;;
    *) wn_die "筆記必須是 .md：$BASE" ;;
esac
NOTE="$NOTE_DIR/$BASE"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 位置判定與 wn_obsolete_reason 一致：檔案第一個非空行是 H1 就看它下方第一個非空行，
# 否則看檔案第一個非空行。
#   設定：已有標記就換掉那一行；沒有就在 H1 後插入「空行 + 標記」（沒有 H1 則在檔頭
#         插入「標記 + 空行」）。
#   清除：拿掉標記，連同當初插入時一起加的那個空行，筆記回到標記前的樣子。
# 原因走 ENVIRON 傳入：awk -v 會解讀反斜線跳脫，原因裡的 \ 會被吃掉。
# 結束碼 3 代表「清除時沒有標記」，由外層判斷。
set +e
WN_MARKER="> 過時：$REASON" WN_MODE="$([ "$CLEAR" -eq 1 ] && printf clear || printf set)" \
LC_ALL=C awk '
    { line[NR] = $0 }
    END {
        first = 0
        for (i = 1; i <= NR; i++) if (line[i] !~ /^[[:space:]]*$/) { first = i; break }
        h1 = (first && line[first] ~ /^# /) ? first : 0

        cand = 0
        for (i = (h1 ? h1 + 1 : 1); i <= NR; i++) if (line[i] !~ /^[[:space:]]*$/) { cand = i; break }
        marked = (cand && line[cand] ~ /^> 過時(：|:)/)

        if (ENVIRON["WN_MODE"] == "clear") {
            if (!marked) exit 3
            skip[cand] = 1
            if (h1 && cand - 1 > h1 && line[cand - 1] ~ /^[[:space:]]*$/) skip[cand - 1] = 1
            else if (!h1 && cand + 1 <= NR && line[cand + 1] ~ /^[[:space:]]*$/) skip[cand + 1] = 1
            for (i = 1; i <= NR; i++) if (!(i in skip)) print line[i]
            exit 0
        }

        if (marked) {
            line[cand] = ENVIRON["WN_MARKER"]
            for (i = 1; i <= NR; i++) print line[i]
        } else if (h1) {
            for (i = 1; i <= h1; i++) print line[i]
            print ""
            print ENVIRON["WN_MARKER"]
            for (i = h1 + 1; i <= NR; i++) print line[i]
        } else {
            print ENVIRON["WN_MARKER"]
            print ""
            for (i = 1; i <= NR; i++) print line[i]
        }
    }
' "$NOTE" > "$TMP"
STATUS=$?
set -e

if [ "$STATUS" -eq 3 ]; then
    printf '沒有過時標記，未改動：%s\n' "$BASE"
    exit 0
fi
[ "$STATUS" -eq 0 ] || wn_die "處理失敗：$BASE"

# 用 cat 寫回而不是 mv：mktemp 建的暫存檔權限是 600，mv 蓋回去會把筆記的權限一起換掉。
cat "$TMP" > "$NOTE"
rm -f "$TMP"
trap - EXIT

if [ "$CLEAR" -eq 1 ]; then
    printf '已取消過時標記：%s\n' "$BASE"
else
    printf '已標為過時：%s\n  以此為準：%s\n' "$BASE" "$REASON"
fi

bash "$SCRIPT_DIR/wn-reindex.sh"
