#!/usr/bin/env bash
#
# 依筆記目錄下的 *.md 重建 index.md。
#
# 索引存在的理由：筆記有數十份，動工前不可能整批讀。索引一份就能掃完，命中才開該筆記。
# 所以每份筆記的第一段要寫「這份在講什麼」，那句會被抓進索引。
#
# 摘要取自 H1 下方第一段（跳過空行、引言、清單、程式碼），過長會截斷。
# 標了過時（`> 過時：…`，由 wn-obsolete.sh 寫入）的筆記不進 index.md，另列在
# obsolete.md，摘要欄換成「以此為準」。沒有過時筆記時不產生 obsolete.md。
# 專案有 ADR 目錄時，index.md 底部另列一張 ADR 表：ADR 多半進版控，決策以它為準。
# 冪等，寫完筆記就重跑。
#
# 執行：bash <本檔所在目錄>/wn-reindex.sh

set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/wn-common.sh"

MAX_LEN=70

# 依 UTF-8 字元數截斷，結果與呼叫端 locale 無關。
# 不能用 ${#s}／${s:0:n}：它們依 LC_CTYPE 計算，AI CLI、cron 這類 LANG 為空的環境
# 會以位元組計，把中文切在字元中間，索引變成非法 UTF-8。
# 這裡固定在 C locale 逐位元組走，延續位元組（0x80–0xBF）不算新字元，截斷點必落在字元邊界。
truncate_utf8() {
    local LC_ALL=C
    local s="$1" max="$2" i=0 chars=0
    local len="${#s}"
    while [ "$i" -lt "$len" ]; do
        case "${s:$i:1}" in
            [$'\x80'-$'\xbf']) ;;
            *)
                chars=$((chars + 1))
                if [ "$chars" -gt "$max" ]; then
                    printf '%s…' "${s:0:$i}"
                    return
                fi
                ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$s"
}

wn_resolve

# 沒有目錄就是還沒有筆記，沒東西可索引。不在這裡建目錄——建目錄是 wn-new.sh
# 與 wn-plan.sh 的事，它們才真的要寫檔案進去。
if ! wn_has_notes; then
    printf '這個專案還沒有施工筆記（%s 不存在）。\n' "$WN_NOTES_DIR"
    exit 0
fi

INDEX="$WN_NOTES_DIR/index.md"
OBSOLETE="$WN_NOTES_DIR/$WN_OBSOLETE_INDEX"

# 先把兩種列各自收進暫存檔，最後再組成索引換上，中途失敗不會留下半份索引。
# index.md 開頭要不要寫「過時筆記另列」取決於有沒有過時筆記，所以列要先收齊。
ROWS="$(mktemp)"
OBS_ROWS="$(mktemp)"
# 最後要 mv 換上去的兩份放在筆記目錄裡、用重導向建立：mktemp 的檔案權限是 600，
# mv 過去會讓索引也變成 600。
TMP="$INDEX.tmp.$$"
OBS_TMP="$OBSOLETE.tmp.$$"
ADR_ROWS="$(mktemp)"
trap 'rm -f "$ROWS" "$OBS_ROWS" "$TMP" "$OBS_TMP" "$ADR_ROWS"' EXIT

BAD_NAMES=""
COUNT=0
OBS_COUNT=0

while IFS= read -r note; do
    [ -n "$note" ] || continue
    base="$(basename "$note")"

    # 檔名規則 YYYY-MM_NN_主題.md，NN 是階段序號不是日。
    # 只提醒不擋，索引照建——擋下來只會讓人繞過這支腳本手改索引。
    if ! printf '%s' "$base" | LC_ALL=C grep -qE "$WN_NOTE_NAME_RE"; then
        BAD_NAMES="$BAD_NAMES  $base"$'\n'
    fi

    title="$(LC_ALL=C sed -n 's/^# //p' "$note" | head -1)"
    [ -n "$title" ] || title="${base%.md}"
    COUNT="$((COUNT + 1))"

    # 過時筆記：摘要欄換成「以此為準」，整列改進 obsolete.md。原因不截斷——
    # 它是指路用的，截斷就可能指不到地方。
    reason="$(wn_obsolete_reason "$note")"
    if [ -n "$reason" ]; then
        printf '| [%s](%s) | %s |\n' "${title//|/\\|}" "$base" "${reason//|/\\|}" >> "$OBS_ROWS"
        OBS_COUNT="$((OBS_COUNT + 1))"
        continue
    fi

    # H1 之後第一段的第一行：跳過空行、引言、清單、表格、程式碼圍籬、分隔線與後續標題。
    # 清單記號後面要有空白才算清單，`**粗體**` 開頭的是一般段落。
    summary="$(LC_ALL=C awk '
        /^# / { seen = 1; next }
        !seen { next }
        /^[[:space:]]*$/ { next }
        /^[-*_ ]+$/ { next }
        /^(#|>|[-*][[:space:]]|\||```|[0-9]+\.)/ { next }
        { print; exit }
    ' "$note")"

    # 開頭就是清單或編號的筆記（沒有導言段）退而求其次，取第一項並去掉標記。
    if [ -z "$summary" ]; then
        summary="$(LC_ALL=C awk '
            /^# / { seen = 1; next }
            !seen { next }
            /^[[:space:]]*$/ { next }
            /^(#|```)/ { next }
            /^[-*_ ]+$/ { next }
            { sub(/^[[:space:]]*([-*][[:space:]]+|[0-9]+\.[[:space:]]*|>[[:space:]]*)/, ""); print; exit }
        ' "$note")"
    fi

    # 表格用 | 當欄位分隔，標題與摘要裡的 | 都要轉義，否則那一列會被切成多欄。
    title="${title//|/\\|}"
    summary="${summary//|/\\|}"
    summary="$(truncate_utf8 "$summary" "$MAX_LEN")"

    printf '| [%s](%s) | %s |\n' "$title" "$base" "$summary" >> "$ROWS"
done <<EOF
$(wn_note_files)
EOF

# ADR 表：連結從 notes/ 往上三層回到專案根。沒進版控的標出來，那種只在本機，
# 份量跟筆記差不多，不能當成團隊共識。
ADR_COUNT=0
# ADR 目錄自帶索引時只放一列指向它，裡面列到的 ADR 不再逐份重列（那份由團隊維護、
# 跟著版控更新，比這張表新）。索引沒提到的、沒進版控的 ADR 仍逐份列出。
while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    adr_idx="$(wn_adr_index "$dir")"
    if [ -n "$adr_idx" ]; then
        adr_title="$dir 自帶的 ADR 索引，裡面列到且進了版控的 ADR 不再逐份列出"
        wn_is_tracked "$adr_idx" || adr_title="${adr_title}（未進版控）"
        printf '| [%s](../../../%s) | %s |\n' "$adr_idx" "$adr_idx" "${adr_title//|/\\|}" >> "$ADR_ROWS"
    fi
done <<EOF
$(wn_adr_dirs)
EOF
# wn_adr_files 的輸出依目錄成群，同一個目錄的索引只查一次，不必每份 ADR 重查。
adr_last_dir=""
adr_idx=""
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    adr_dir="$(dirname "$rel")"
    if [ "$adr_dir" != "$adr_last_dir" ]; then
        adr_idx="$(wn_adr_index "$adr_dir")"
        adr_last_dir="$adr_dir"
    fi
    if [ -n "$adr_idx" ] && wn_is_tracked "$rel" \
        && grep -qF "$(basename "$rel" .md)" "$WN_ROOT/$adr_idx"; then
        ADR_COUNT="$((ADR_COUNT + 1))"
        continue
    fi
    adr_title="$(LC_ALL=C sed -n 's/^# //p' "$WN_ROOT/$rel" | head -1)"
    [ -n "$adr_title" ] || adr_title="$(basename "$rel" .md)"
    wn_is_tracked "$rel" || adr_title="${adr_title}（未進版控）"
    printf '| [%s](../../../%s) | %s |\n' "$rel" "$rel" "${adr_title//|/\\|}" >> "$ADR_ROWS"
    ADR_COUNT="$((ADR_COUNT + 1))"
done <<EOF
$(wn_adr_files)
EOF

{
    printf '%s\n\n' '# 施工筆記索引'
    printf '%s\n' '由 `wn-reindex.sh` 產生，不要手動編輯。新增筆記後重跑一次。'
    printf '\n%s\n' '動工前掃這份，找到相關主題再開該筆記；沒命中就不用讀。'
    if [ "$OBS_COUNT" -gt 0 ]; then
        printf '%s\n' "已過時的筆記列在 [${WN_OBSOLETE_INDEX}](${WN_OBSOLETE_INDEX})，動工前不必讀。"
    fi
    printf '\n%s\n%s\n' '| 筆記 | 摘要 |' '|---|---|'
    cat "$ROWS"
    if [ "$ADR_COUNT" -gt 0 ]; then
        printf '\n%s\n\n' '## ADR（決策以此為準）'
        printf '%s\n' '這個專案有架構決策紀錄（ADR）。ADR 多半進版控、團隊共享，筆記多半只在本機，所以**決策與理由以 ADR 為準**：先掃這張表，命中再開該 ADR；筆記的說法跟 ADR 不一致時，照 ADR 做並回頭改筆記。'
        printf '%s\n' '這張表截至上次重建索引，之後新增的 ADR 以目錄的實際內容為準。'
        printf '\n%s\n%s\n' '| ADR | 標題 |' '|---|---|'
        cat "$ADR_ROWS"
    fi
} > "$TMP"
mv "$TMP" "$INDEX"

# 沒有過時筆記就不留 obsolete.md：留著的話，它會是一份內容過期的索引。
if [ "$OBS_COUNT" -gt 0 ]; then
    {
        printf '%s\n\n' '# 過時筆記索引'
        printf '%s\n' '由 `wn-reindex.sh` 產生，不要手動編輯。筆記用 `wn-obsolete.sh` 標過時或取消。'
        printf '\n%s\n\n' '這裡的筆記已過時，動工前不必讀；要找現行的規則或做法，以「以此為準」那欄為準。'
        printf '%s\n%s\n' '| 筆記 | 以此為準 |' '|---|---|'
        cat "$OBS_ROWS"
    } > "$OBS_TMP"
    mv "$OBS_TMP" "$OBSOLETE"
else
    rm -f "$OBSOLETE"
fi

rm -f "$ROWS" "$OBS_ROWS" "$TMP" "$OBS_TMP" "$ADR_ROWS"
trap - EXIT

if [ "$OBS_COUNT" -gt 0 ]; then
    printf '已重建 %s（%s 份筆記，其中 %s 份過時，另列在 %s）\n' "$INDEX" "$COUNT" "$OBS_COUNT" "$WN_OBSOLETE_INDEX"
else
    printf '已重建 %s（%s 份筆記）\n' "$INDEX" "$COUNT"
fi

if [ "$ADR_COUNT" -gt 0 ]; then
    printf '索引底部另列 %s 份 ADR（決策以 ADR 為準）\n' "$ADR_COUNT"
fi

if [ -n "$BAD_NAMES" ]; then
    printf '\n檔名不符 YYYY-MM_NN_主題.md，請改名：\n%s' "$BAD_NAMES" >&2
fi
