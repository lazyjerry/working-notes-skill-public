#!/usr/bin/env bash
#
# 切換施工筆記要不要進版控。實際做的事是換掉 docs/working-notes-skill/.gitignore。
#
# 預設 untracked：筆記只存在本機。這對「筆記寫的是內部取捨與踩過的坑」比較安全，
# 但換台機器或換個人接手就什麼都沒有。要讓筆記跟著 repo 走就切 tracked。
#
# tracked 模式仍然忽略 backup-*/——那是 adopt 的一次性產物，不該進版控。
#
# 用法:
#   bash wn-vcs.sh              印出目前狀態
#   bash wn-vcs.sh tracked      筆記進版控
#   bash wn-vcs.sh untracked    筆記不進版控（預設）
#     --force                   覆寫手動改過的 .gitignore

set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/wn-common.sh"

WANT=""
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        tracked|untracked) WANT="$1" ;;
        --force) FORCE=1 ;;
        *) wn_die "用法：wn-vcs.sh [tracked|untracked] [--force]" ;;
    esac
    shift
done

wn_resolve

# 查詢與切換都不建目錄——沒有筆記就沒有版控狀態可談
if ! wn_has_notes; then
    printf '這個專案還沒有施工筆記（%s 不存在）。\n' "$WN_NOTES_DIR"
    printf '先用 wn-new.sh 建第一份，目錄與 .gitignore 會一併建立。\n'
    exit 0
fi

TARGET="$WN_BASE_DIR/.gitignore"
MODE="$(wn_vcs_mode)"

describe() {
    case "$1" in
        untracked) printf '不進版控（筆記只存在本機）' ;;
        tracked)   printf '進版控（backup-*/ 除外）' ;;
        custom)    printf '自訂（.gitignore 被手動改過）' ;;
        none)      printf '沒有 .gitignore' ;;
    esac
}

if [ -z "$WANT" ]; then
    printf '筆記目錄：%s\n' "$WN_NOTES_DIR"
    printf '版控狀態：%s\n' "$(describe "$MODE")"
    printf '.gitignore：%s\n' "$TARGET"
    printf '\n切換：bash wn-vcs.sh tracked｜bash wn-vcs.sh untracked\n'
    exit 0
fi

if [ "$MODE" = "$WANT" ]; then
    printf 'ℹ️  已經是「%s」，未改動。\n' "$(describe "$WANT")"
    exit 0
fi

# 手動改過的不擅自覆寫——那是使用者自己加的規則，蓋掉不會有任何提示
if [ "$MODE" = "custom" ] && [ "$FORCE" -eq 0 ]; then
    printf '⚠️  %s 被手動改過，不覆寫。\n' "$TARGET" >&2
    printf '    確定要換成標準的「%s」請加 --force。\n' "$(describe "$WANT")" >&2
    exit 1
fi

[ -f "$TARGET" ] && cp "$TARGET" "$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
cp "$(wn_assets_dir)/gitignore-$WANT" "$TARGET"

printf '✅ 已切換為「%s」\n' "$(describe "$WANT")"

if [ "$WANT" = "tracked" ]; then
    COUNT="$(wn_note_count)"
    printf '\n%s 份筆記與 plans/ 現在會出現在 git status 上。\n' "$COUNT"
    printf '這些內容會被推上遠端、被所有能讀該 repo 的人看到——確認裡面沒有\n'
    printf '不該外流的東西再提交。\n'
    printf '\n要納入版控：git add %s\n' "${WN_BASE_DIR#"$WN_ROOT"/}"
else
    printf '\n筆記不再進版控。**已經提交過的不會自動消失**，\n'
    printf '要從版控移除（保留本機檔案）：\n'
    printf '  git rm -r --cached %s\n' "${WN_BASE_DIR#"$WN_ROOT"/}"
fi
