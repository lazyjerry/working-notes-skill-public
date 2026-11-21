#!/usr/bin/env bash
#
# 一次性：把專案既有的筆記目錄改名到標準路徑 docs/working-notes-skill/notes/。
#
# 因為筆記本來就留在專案內，這只是改個路徑名稱，不是跨檔案系統搬遷。
#
# 預設 dry-run，只列清單、一個檔都不動；要真的做得加 --yes。
#
# 用法:
#   bash scripts/wn-adopt.sh [--from <相對路徑>] [--yes]
#                            [--rewrite-refs] [--skip-refs <樣式>]...
#     --from          沒給就自動找 docs/notes、notes、working-knowledge、docs/working-notes
#     --yes           真的執行（否則只列清單）
#     --rewrite-refs  一併把專案內指向舊路徑的引用改成新路徑
#     --skip-refs     改寫時跳過符合樣式的檔案（相對專案根的 glob，可重複給）
#
# 引用改寫預設「不做」是刻意的：專案裡指向筆記目錄的檔案，往往有一大半是執行後的
# 計畫存檔、研究報告與一次性腳本——那些是當時的紀錄，改它們等於竄改歷史。哪些該改
# 只有人知道，所以預設只列出來，要改得明講。
#
# 執行：bash scripts/wn-adopt.sh --from docs/notes

set -euo pipefail

SKILL_SCRIPTS="$(cd "$(dirname "$0")/../skills/working-notes-skill/scripts" && pwd)"
. "$SKILL_SCRIPTS/wn-common.sh"

FROM=""
APPLY=0
REWRITE=0
SKIPS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --from) [ $# -ge 2 ] || wn_die "--from 需要一個值"; shift; FROM="$1" ;;
        --yes) APPLY=1 ;;
        --rewrite-refs) REWRITE=1 ;;
        --skip-refs) [ $# -ge 2 ] || wn_die "--skip-refs 需要一個值"; shift; SKIPS="$SKIPS$1"$'\n' ;;
        *) wn_die "未知參數：$1" ;;
    esac
    shift
done

# 相對路徑是否符合任一 --skip-refs 樣式
wn_skipped() {
    local rel="$1" pat
    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        # shellcheck disable=SC2254
        case "$rel" in $pat) return 0 ;; esac
    done <<EOF
$SKIPS
EOF
    return 1
}

# 就地改寫檔案。不用 sed -i：BSD 要寫 `-i ''`、GNU 要寫 `-i`，兩邊不相容。
# 用 cat 寫回而不是 mv，保留原檔的權限。
wn_sed_inplace() {
    local expr="$1" file="$2" tmp
    tmp="$(mktemp)"
    if LC_ALL=C sed "$expr" "$file" > "$tmp"; then
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        wn_die "改寫失敗：$file"
    fi
}

# 尾端的 / 會讓目錄深度多算一層
FROM="${FROM%/}"

wn_resolve

# 自動找既有筆記目錄：存在、且裡面有 .md
if [ -z "$FROM" ]; then
    for cand in docs/notes notes docs/working-notes working-knowledge; do
        d="$WN_ROOT/$cand"
        [ -d "$d" ] || continue
        if [ -n "$(LC_ALL=C find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null | head -1)" ]; then
            FROM="$cand"
            break
        fi
    done
fi

[ -n "$FROM" ] || wn_die "找不到既有的筆記目錄，請用 --from 指定（相對於 ${WN_ROOT}）"

SRC="$WN_ROOT/$FROM"
[ -d "$SRC" ] || wn_die "來源目錄不存在：$SRC"

SRC_ABS="$(cd "$SRC" && pwd -P)"
[ "$SRC_ABS" = "$WN_NOTES_DIR" ] && wn_die "來源已經是標準路徑，不需要 adopt：$SRC_ABS"
[ "$SRC_ABS" = "$WN_ROOT" ] && wn_die "來源不能是專案根本身"

printf '專案根　：%s\n' "$WN_ROOT"
printf '來源目錄：%s\n' "$SRC_ABS"
printf '目標目錄：%s\n' "$WN_NOTES_DIR"
printf '\n'

# ---- 盤點 ----

NOTES="$(LC_ALL=C find "$SRC_ABS" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' | LC_ALL=C sort)"
N_TOTAL="$(printf '%s' "$NOTES" | grep -c . || true)"

printf '【1】會搬的筆記：%s 份（舊的 index.md 不搬，直接重生）\n' "$N_TOTAL"

BAD=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    b="$(basename "$f")"
    printf '%s' "$b" | LC_ALL=C grep -qE "$WN_NOTE_NAME_RE" || BAD="$BAD  $b"$'\n'
done <<EOF
$NOTES
EOF

if [ -n "$BAD" ]; then
    printf '    其中檔名不符 YYYY-MM_NN_主題.md（照搬，索引會另外提醒）：\n%s' "$BAD"
else
    printf '    檔名全部符合 YYYY-MM_NN_主題.md\n'
fi

# 專案內指向舊路徑的引用。排除來源目錄自己與各種產生物目錄。
printf '\n【2】專案內指向 %s 的引用：\n' "$FROM"
REFS="$(LC_ALL=C grep -rlF "$FROM" "$WN_ROOT" \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
    --exclude-dir="$(basename "$SRC_ABS")" 2>/dev/null | LC_ALL=C sort || true)"
# grep 的 --exclude-dir 只認名稱，來源目錄同名於他處時仍會被掃到，這裡再濾一次
REFS="$(printf '%s\n' "$REFS" | LC_ALL=C grep -v "^$SRC_ABS/" || true)"

REFS_TODO=""
REFS_SKIP=""
if [ -z "$REFS" ]; then
    printf '    無\n'
else
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$WN_ROOT"/}"
        c="$(LC_ALL=C grep -cF "$FROM" "$f" || true)"
        if wn_skipped "$rel"; then
            REFS_SKIP="$REFS_SKIP$f"$'\n'
            printf '    [跳過] %s（%s 處）\n' "$rel" "$c"
        else
            REFS_TODO="$REFS_TODO$f"$'\n'
            printf '    %s（%s 處）\n' "$rel" "$c"
        fi
    done <<EOF
$REFS
EOF
    if [ "$REWRITE" -eq 1 ]; then
        printf '    → 加了 --rewrite-refs，上列未跳過的會被改寫成新路徑\n'
    else
        printf '    → 預設不改寫。這裡面常有執行後的計畫存檔與一次性腳本，\n'
        printf '      改它們等於竄改當時的紀錄。要改請加 --rewrite-refs，\n'
        printf '      並用 --skip-refs "docs/plans/*" 這類樣式排除歷史檔案。\n'
    fi
fi

# 筆記內跨出目錄的相對連結：改名後深度變了會失準
DEPTH_SRC="$(printf '%s' "$FROM" | LC_ALL=C tr -cd '/' | wc -c | tr -d ' ')"
DEPTH_DST="$(printf '%s' "${WN_NOTES_DIR#"$WN_ROOT"/}" | LC_ALL=C tr -cd '/' | wc -c | tr -d ' ')"
DEPTH_DIFF="$((DEPTH_DST - DEPTH_SRC))"

printf '\n【3】筆記內跨出目錄的相對連結（](../…)）：'
# 排除 index.md：它不會被搬，會被 wn-reindex.sh 重生
UPLINKS="$(LC_ALL=C grep -rlE '\]\(\.\./' "$SRC_ABS" --include='*.md' --exclude='index.md' 2>/dev/null | LC_ALL=C sort || true)"
if [ -z "$UPLINKS" ]; then
    printf '無\n'
else
    printf '\n'
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        c="$(LC_ALL=C grep -cE '\]\(\.\./' "$f" || true)"
        printf '    %s（%s 處）\n' "$(basename "$f")" "$c"
    done <<EOF
$UPLINKS
EOF
    printf '    目錄深度 %s → %s，差 %s 層，每條要補 %s 個 ../\n' \
        "$DEPTH_SRC" "$DEPTH_DST" "$DEPTH_DIFF" "$DEPTH_DIFF"
fi

# 舊索引是不是別的腳本產生的
printf '\n【4】舊索引的產生方式：'
OLD_INDEX="$SRC_ABS/index.md"
if [ -f "$OLD_INDEX" ]; then
    OWNER="$(LC_ALL=C sed -n 's/.*由 `\([^`]*\)` 產生.*/\1/p' "$OLD_INDEX" | head -1)"
    if [ -n "$OWNER" ]; then
        printf '由 `%s` 產生\n' "$OWNER"
        printf '    adopt 完成後這支已被 wn-reindex.sh 取代。刪它之前，先把所有提到它的說明一起改掉：\n'
        LC_ALL=C grep -rlF "$(basename "$OWNER")" "$WN_ROOT" \
            --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor 2>/dev/null |
            LC_ALL=C sort | while IFS= read -r f; do printf '      %s\n' "${f#"$WN_ROOT"/}"; done
    else
        printf '沒有自述產生者\n'
    fi
else
    printf '沒有 index.md\n'
fi

if [ "$APPLY" -eq 0 ]; then
    printf '\n--- 這是 dry-run，什麼都沒改。確認無誤後加 --yes 執行。---\n'
    exit 0
fi

# ---- 實際執行 ----

printf '\n=== 開始執行 ===\n'

BACKUP="$WN_BASE_DIR/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -R "$SRC_ABS/." "$BACKUP/"
printf '已備份來源目錄 → %s\n' "$BACKUP"

# 引用改寫前也備份一份
if [ "$REWRITE" -eq 1 ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        # 照相對路徑存：只留檔名的話，不同目錄的同名檔（例如好幾份 README.md）會互相覆蓋
        orig="$BACKUP/refs-orig/${f#"$WN_ROOT"/}"
        mkdir -p "$(dirname "$orig")"
        cp "$f" "$orig"
    done <<EOF
$REFS_TODO
EOF
fi

# 搬檔。git mv 讓版控看得懂是改名，不在版控就一般 mv。
mkdir -p "$WN_NOTES_DIR"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if git -C "$WN_ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        git -C "$WN_ROOT" mv "$f" "$WN_NOTES_DIR/"
    else
        mv "$f" "$WN_NOTES_DIR/"
    fi
done <<EOF
$NOTES
EOF
printf '已搬 %s 份筆記到 %s\n' "$N_TOTAL" "$WN_NOTES_DIR"

# 舊 index.md 不搬，直接丟掉——開頭說明文字不同，wn-reindex.sh 會重生一份
[ -f "$OLD_INDEX" ] && rm -f "$OLD_INDEX" && printf '已移除舊 index.md（wn-reindex.sh 會重生）\n'

wn_ensure_gitignore

# 補相對連結的層數
if [ -n "$UPLINKS" ] && [ "$DEPTH_DIFF" -gt 0 ]; then
    PREFIX=""
    i=0
    while [ "$i" -lt "$DEPTH_DIFF" ]; do PREFIX="$PREFIX../"; i="$((i + 1))"; done
    n=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        target="$WN_NOTES_DIR/$(basename "$f")"
        [ -f "$target" ] || continue
        wn_sed_inplace "s|](\.\./|](${PREFIX}../|g" "$target"
        n="$((n + 1))"
    done <<EOF
$UPLINKS
EOF
    printf '已為 %s 份筆記的跨層連結各補 %s 個 ../\n' "$n" "$DEPTH_DIFF"
fi

# 改寫外部引用的路徑字串（只在明講 --rewrite-refs 時）
NEW_REL="${WN_NOTES_DIR#"$WN_ROOT"/}"
if [ "$REWRITE" -eq 1 ] && [ -n "$REFS_TODO" ]; then
    # 來源路徑要當字面字串比對，先把 sed 的特殊字元跳脫掉（docs/my.notes 的 . 不該配到任意字元）
    FROM_RE="$(printf '%s' "$FROM" | LC_ALL=C sed 's/[][\.*^$|]/\\&/g')"
    n=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        wn_sed_inplace "s|$FROM_RE|$NEW_REL|g" "$f"
        printf '  已改寫 %s\n' "${f#"$WN_ROOT"/}"
        n="$((n + 1))"
    done <<EOF
$REFS_TODO
EOF
    printf '共改寫 %s 個檔案的路徑引用（%s → %s）\n' "$n" "$FROM" "$NEW_REL"
fi

bash "$SKILL_SCRIPTS/wn-reindex.sh"

printf '\n完成。還沒做的事：\n'
if [ "$REWRITE" -eq 0 ] && [ -n "$REFS" ]; then
    printf '  0. 上面【2】列出的引用還指著 %s，逐一決定要改哪些\n' "$FROM"
fi
printf '  1. 檢查上面【4】列出的檔案，把「跑舊索引腳本」那類敘述改成 wn-new.sh／wn-reindex.sh\n'
printf '  2. 確認沒有別處呼叫後，刪掉舊的索引腳本\n'
printf '  3. 核對無誤後自行刪除備份：%s\n' "$BACKUP"
