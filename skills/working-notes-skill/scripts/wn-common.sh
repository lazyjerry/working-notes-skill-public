#!/usr/bin/env bash
#
# 共用函式：解析專案根與筆記目錄。由 wn-new.sh / wn-reindex.sh / wn-plan.sh /
# wn-vcs.sh / wn-obsolete.sh 與 repo 的 scripts/wn-adopt.sh source。
#
# 中文安全：專案路徑與筆記檔名大量含中文。macOS 的 en_US.UTF-8 對 CJK 沒有 collation
# 權重，awk 的 == 與 sort 會靜默出錯；bash 3.2 的 echo 在「變數展開緊接全形字元」時
# 會掉一個位元組。所以本檔一律 printf 輸出、比較與排序加 LC_ALL=C。
#
# 本檔不可直接執行。

# 路徑寫死、不開設定：唯一能讓它跑掉的是「專案根解析錯了」，那是可以查的；
# 多一個可覆寫的位置只會讓每個專案的筆記可能落在不同地方，還要為它寫一堆
# 「不准指到專案根」的防護。真的需要改再說。
WN_SUBDIR="docs/working-notes-skill"
WN_NOTE_NAME_RE='^[0-9]{4}-[0-9]{2}_[0-9]{2}_.+\.md$'

# 過時筆記另列一份索引，主索引只放還有效的筆記，動工前掃起來不被干擾。
WN_OBSOLETE_INDEX="obsolete.md"

wn_die() {
    printf '%s\n' "$1" >&2
    exit 1
}

# 專案根：git → 往上找標記檔 → CWD
wn_project_root() {
    local root
    if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ]; then
        printf '%s' "$root"
        return
    fi

    local dir
    dir="$PWD"
    while [ "$dir" != "/" ]; do
        for marker in .git CLAUDE.md AGENTS.md package.json composer.json; do
            if [ -e "$dir/$marker" ]; then
                printf '%s' "$dir"
                return
            fi
        done
        dir="$(dirname "$dir")"
    done

    printf '%s' "$PWD"
}

# 解析後設定四個變數：WN_ROOT、WN_BASE_DIR、WN_NOTES_DIR、WN_PLANS_DIR
wn_resolve() {
    WN_ROOT="$(wn_project_root)"
    WN_BASE_DIR="$WN_ROOT/$WN_SUBDIR"
    WN_NOTES_DIR="$WN_BASE_DIR/notes"
    WN_PLANS_DIR="$WN_BASE_DIR/plans"
}

# 只有「真的要寫一份檔案進去」的腳本才呼叫這支。
#
# 讀取或查詢絕不能建目錄：那會讓代理光是看一眼，就在每個路過的 repo 種下
# docs/working-notes-skill/ 與 .gitignore。有筆記要存的時候再建就好。
wn_ensure_dir() {
    if [ ! -d "$WN_NOTES_DIR" ]; then
        mkdir -p "$WN_NOTES_DIR" || wn_die "無法建立 $WN_NOTES_DIR"
        printf '已建立筆記目錄：%s\n' "$WN_NOTES_DIR" >&2
    fi
    wn_ensure_gitignore
}

# 查詢用：目錄不存在就是還沒有筆記，不要順手建起來
wn_has_notes() {
    [ -d "$WN_NOTES_DIR" ]
}

wn_assets_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd
}

# 中文標題 → 檔名。空白與檔案系統／URL 會出事的符號一律換成 -，
# 連續的 - 收成一個，頭尾的 - 去掉。中文字本身完整保留。
#
# 半形符號用 tr：兩邊都是 ASCII，UTF-8 的續接位元組都 >= 0x80，不會被誤傷。
# 全形符號一定要用 sed 的字面字串取代，**不能塞進 tr**——tr 是逐位元組運作的，
# 把多位元組字元放進字元集會拆散它，產生無效 UTF-8。
wn_slug() {
    printf '%s' "$1" |
        LC_ALL=C tr ' \t/:?*"<>|\\()[]{}' '-' |
        LC_ALL=C sed \
            -e 's/（/-/g' -e 's/）/-/g' -e 's/〔/-/g' -e 's/〕/-/g' \
            -e 's/「/-/g' -e 's/」/-/g' -e 's/『/-/g' -e 's/』/-/g' \
            -e 's/【/-/g' -e 's/】/-/g' -e 's/〈/-/g' -e 's/〉/-/g' \
            -e 's/：/-/g' -e 's/？/-/g' -e 's/！/-/g' -e 's/、/-/g' \
            -e 's/，/-/g' -e 's/。/-/g' -e 's/；/-/g' -e 's/｜/-/g' \
            -e 's/　/-/g' \
            -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# .gitignore 放 notes/ 的上一層（docs/working-notes-skill/），那層還會放 plans/
# 與 adopt 的備份，一起蓋掉比較省事。既有的不覆寫——切換版控狀態走 wn-vcs.sh。
wn_ensure_gitignore() {
    local target="$WN_BASE_DIR/.gitignore"
    [ -e "$target" ] && return
    [ -d "$WN_BASE_DIR" ] || return

    local src="$(wn_assets_dir)/gitignore-untracked"
    [ -f "$src" ] || return

    cp "$src" "$target" && printf '已佈署 .gitignore：%s\n' "$target" >&2
}

# 目前版控狀態：untracked｜tracked｜custom｜none
wn_vcs_mode() {
    local target="$WN_BASE_DIR/.gitignore"
    [ -f "$target" ] || { printf 'none'; return; }

    local assets="$(wn_assets_dir)"
    if diff -q "$target" "$assets/gitignore-untracked" >/dev/null 2>&1; then
        printf 'untracked'
    elif diff -q "$target" "$assets/gitignore-tracked" >/dev/null 2>&1; then
        printf 'tracked'
    else
        printf 'custom'
    fi
}

# 筆記檔清單（不含兩份索引），依檔名排序。LC_ALL=C 讓中文檔名逐位元組比較。
wn_note_files() {
    LC_ALL=C find "$WN_NOTES_DIR" -maxdepth 1 -type f -name '*.md' \
        ! -name 'index.md' ! -name "$WN_OBSOLETE_INDEX" 2>/dev/null | LC_ALL=C sort
}

# 印出筆記的過時原因（「以此為準」），沒標過時就印空字串。
#
# 標記是 H1 下方第一個非空行的 `> 過時：<原因>`；沒有 H1 時看檔案第一個非空行。
# 只認這一個位置，內文其他地方引用「過時」兩字不會被誤判。
wn_obsolete_reason() {
    LC_ALL=C awk '
        /^[[:space:]]*$/ { next }
        !started { started = 1; if ($0 ~ /^# /) next }
        { if (sub(/^> 過時(：|:)[[:space:]]*/, "")) print; exit }
    ' "$1"
}

wn_note_count() {
    wn_note_files | grep -c . || true
}

# ADR（架構決策紀錄）多半進版控、團隊共享；施工筆記多半只在本機。同一個決策兩邊都
# 記時以 ADR 為準，所以索引要把 ADR 一起列出來，建筆記時也要提醒。
#
# 認三種位置：docs/adr（含多 context 的 src/<ctx>/docs/adr）、docs/decisions（MADR
# 工具的預設）、.agents/adr。只看目錄名稱，不管裡面的格式。
# 印出相對專案根的目錄，一行一個，依路徑排序。
wn_adr_dirs() {
    local d
    while IFS= read -r d; do
        # 不能寫成 `[ -n ] && printf`：沒有 ADR 時那行回傳 1，呼叫端在 set -e 下
        # 用 ADR_DIRS="$(wn_adr_dirs)" 接結果會整支中止
        if [ -n "$d" ]; then printf '%s\n' "${d#"$WN_ROOT"/}"; fi
    done <<EOT
$(LC_ALL=C find "$WN_ROOT" -maxdepth 5 \
    \( -name node_modules -o -name .git -o -name vendor \) -prune -o \
    -type d \( -path '*/docs/adr' -o -path '*/docs/decisions' -o -path '*/.agents/adr' \) \
    -print 2>/dev/null | LC_ALL=C sort)
EOT
}

# ADR 檔案清單（相對專案根），README、index 與範本不算
wn_adr_files() {
    local dir f
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        while IFS= read -r f; do
            if [ -n "$f" ]; then printf '%s\n' "${f#"$WN_ROOT"/}"; fi
        done <<EOT
$(LC_ALL=C find "$WN_ROOT/$dir" -maxdepth 1 -type f -name '*.md' \
    ! -iname 'README.md' ! -iname 'index.md' ! -iname 'template*.md' 2>/dev/null | LC_ALL=C sort)
EOT
    done <<EOT
$(wn_adr_dirs)
EOT
}

# 檔案有沒有進 git 版控（相對專案根）。不是 git 專案一律當沒進。
wn_is_tracked() {
    git -C "$WN_ROOT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

# ADR 目錄自帶的索引（相對專案根）：目錄第一層的 README.md 或 index.md，內文至少
# 提到一份該目錄 ADR 的檔名（不含 .md）才算。log4brains 這類工具的 index.md 是
# 歡迎頁、不列 ADR，不能當索引。沒有就不印。
wn_adr_index() {
    local dir="$1" idx f
    while IFS= read -r idx; do
        [ -n "$idx" ] || continue
        while IFS= read -r f; do
            if [ -n "$f" ] && [ "$(dirname "$f")" = "$dir" ] \
                && grep -qF "$(basename "$f" .md)" "$idx"; then
                printf '%s\n' "${idx#"$WN_ROOT"/}"
                return 0
            fi
        done <<EOT
$(wn_adr_files)
EOT
    done <<EOT
$(LC_ALL=C find "$WN_ROOT/$dir" -maxdepth 1 -type f \( -iname 'README.md' -o -iname 'index.md' \) 2>/dev/null | LC_ALL=C sort)
EOT
    return 0
}
