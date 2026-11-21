#!/bin/sh
#
# 把「施工筆記」規則段注入指定的 AI 指令檔（AGENTS.md／CLAUDE.md／GEMINI.md）。
#
# 用標記區塊包住自己的內容，區塊外的東西一個字不動。重跑會就地更新區塊（冪等），
# 動檔前一定留一份備份——指令檔是每次 session 都讀的東西。
#
# 用法:
#   sh scripts/wn-install.sh <目標路徑> [--skill-dir <路徑>] [--after <標記字串>]
#     <目標路徑>     目錄（注入其下的 AGENTS.md／CLAUDE.md／GEMINI.md）或單一 .md 檔
#     --skill-dir    skill 的安裝位置，決定規則段裡寫出的腳本路徑
#                    預設為本 repo 的 skills/working-notes-skill（從腳本自身位置推導）；
#                    目標檔已有區塊時**沿用它裡面現有的路徑**，除非這個參數有明確給
#     --after        找到這行標記就插在它後面；沒指定或找不到一律插在**檔案開頭**
#
# 為什麼預設插開頭：這是「動工前先做什麼」的規則，擺在檔尾等於排在一堆其他指引
# 後面才被讀到。指令檔越長越明顯。
#
# 目標路徑不給就列出偵測到的候選並結束——猜使用者用哪套工具只會裝錯地方。
#
# 結束碼: 0 成功或無事可做；1 參數或路徑錯誤

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET=""
SKILL_DIR="$REPO_ROOT/skills/working-notes-skill"
SKILL_DIR_EXPLICIT=0
ANCHOR=""
TS="$(date +%Y%m%d-%H%M%S)"

while [ $# -gt 0 ]; do
    case "$1" in
        --skill-dir|--after)
            # 少了值就講清楚：dash 對空的參數列 shift 會直接報 shell 內部錯誤
            [ $# -ge 2 ] || { printf '❌ %s 需要一個值\n' "$1" >&2; exit 1; }
            if [ "$1" = "--skill-dir" ]; then SKILL_DIR="$2"; SKILL_DIR_EXPLICIT=1; else ANCHOR="$2"; fi
            shift
            ;;
        -*) printf '❌ 未知參數: %s\n' "$1" >&2; exit 1 ;;
        *) TARGET="$1" ;;
    esac
    shift
done

usage_targets() {
    printf '用法: sh scripts/wn-install.sh <目標路徑> [--skill-dir <路徑>] [--after <標記字串>]\n\n' >&2
    printf '未指定目標。偵測到以下既有的 AI 指令檔，挑一個傳進來：\n' >&2
    found=0
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" \
             "$HOME/.gemini/GEMINI.md" "$HOME/.ai-global/AGENTS.md"; do
        [ -f "$f" ] || continue
        printf '  %s\n' "$f" >&2
        found=1
    done
    [ "$found" -eq 0 ] && printf '  （沒有偵測到，請自行指定路徑）\n' >&2
    exit 1
}

[ -n "$TARGET" ] || usage_targets
[ -d "$SKILL_DIR" ] || { printf '❌ skill 目錄不存在: %s\n' "$SKILL_DIR" >&2; exit 1; }

SKILL_SCRIPTS="$(cd "$SKILL_DIR/scripts" && pwd)"

# 家目錄前綴換回 ~，規則段裡的路徑才不會寫死某台機器的使用者名稱
case "$SKILL_SCRIPTS" in
    "$HOME"/*) SCRIPTS_DISPLAY="~/${SKILL_SCRIPTS#"$HOME"/}" ;;
    *) SCRIPTS_DISPLAY="$SKILL_SCRIPTS" ;;
esac

MARKER_BEGIN="<!-- BEGIN working-notes-skill:notes -->"
MARKER_END="<!-- END working-notes-skill:notes -->"

# 重跑通常是為了更新規則文字，不是為了換腳本位置。沒明講 --skill-dir 時就沿用
# 目標檔裡現有的路徑——否則「從 repo 重跑一次升級措辭」會靜默把全域設定的路徑
# 從佈署位置改指到 repo，而且看起來一切正常。
inherit_scripts_path() {
    f="$1"
    [ "$SKILL_DIR_EXPLICIT" -eq 1 ] && return 0
    [ -f "$f" ] || return 0
    grep -qF "$MARKER_BEGIN" "$f" || return 0

    # 抓區塊裡任何以 /scripts 結尾的路徑，不綁定某一版的措辭——區塊文字改版時
    # 若這裡跟不上，重跑就會靜默把路徑改掉，正是這支函式要防的事。
    # 只看區塊內：指令檔其他段落也可能提到別的工具的 …/scripts 路徑，掃整份檔案會
    # 把那個路徑當成自己的沿用下來。
    existing="$(LC_ALL=C awk -v B="$MARKER_BEGIN" -v E="$MARKER_END" '
        index($0, B) > 0 { inblock=1 }
        inblock { print }
        inblock && index($0, E) > 0 { exit }
    ' "$f" | LC_ALL=C sed -n 's|.*[`( ]\(/[^`) ]*/scripts\)[/`) ].*|\1|p;s|.*[`( ]\(~/[^`) ]*/scripts\)[/`) ].*|\1|p' | head -1)"
    [ -n "$existing" ] || return 0
    [ "$existing" = "$SCRIPTS_DISPLAY" ] && return 0

    SCRIPTS_DISPLAY="$existing"
    printf 'ℹ️  沿用檔案裡現有的腳本路徑: %s\n' "$existing"
    printf '    要改成別的位置請明確指定 --skill-dir\n'
}

make_block() {
cat <<EOF
$MARKER_BEGIN
# 施工筆記優先參考

每個專案的施工結論記在該專案自己的施工筆記裡，動工前先掃索引，任務收尾補一份。

- **動工前**：讀 \`<專案根>/docs/working-notes-skill/notes/index.md\`——標題加一句摘要，一份就掃得完。**掃索引、命中才開該筆記**，不要整批讀；沒命中就直接動工。沒有這個檔案就是這個專案還沒有筆記。過時的筆記另列在同目錄的 \`obsolete.md\`，不必讀。
- **專案有 ADR 時以 ADR 為準**：ADR（\`docs/adr/\`、\`docs/decisions/\`、\`.agents/adr/\`）多半進版控、團隊共享，筆記多半只在本機。index.md 底部的 ADR 表先掃，命中就開該 ADR；筆記跟 ADR 說法不一致時照 ADR 做並回頭改筆記。值得寫 ADR 的決策，理由寫進 ADR，筆記只寫一句指向它。
- **專案根**是含 \`.git\` 或 \`CLAUDE.md\` 的那一層，不是編輯器的工作目錄——工作目錄常常開在專案的上一層。
- **任務收尾**：做完有結論的任務（定了做法、改了設計、踩到坑並解掉），收工前補一份筆記；純查詢、純問答、只讀不改的任務不必寫。
- **動到筆記就講是哪一份**：讀到筆記內容、或寫入筆記之後，在回覆裡列出實際的檔案（讀：掃了 index.md 加上命中後開的那幾份；寫：新建或改動的檔加上索引已重建）。路徑用**專案根的相對位置**，不要貼絕對路徑。使用者要能自己去翻那份檔案、驗證結論的出處。
- **要寫筆記、把筆記標成過時、留 Plan Mode 計畫檔，或改筆記的版控設定時**：載入 \`working-notes-skill\` skill，照它的流程走，不要自己拼檔名或手改索引。腳本在 \`$SCRIPTS_DISPLAY/\`。
- 收的是**這個專案**的結論；換到別的專案仍成立的通則不寫在這裡。
$MARKER_END
EOF
}

# 就地把既有區塊換成現行版本：保留區塊原位置，區塊外內容原樣保留。
# LC_ALL=C 不可省略：macOS 內建 awk 在 UTF-8 locale 下比較多位元組字串會失準，
# 而這些指令檔通篇中文，標記比對必須走位元組語意。
refresh_file() {
    f="$1"

    blk="$f.wnblock.$$"
    cur="$f.wncurrent.$$"
    tmp="$f.wninject.$$"
    trap 'rm -f "$blk" "$cur" "$tmp"' EXIT INT TERM
    make_block > "$blk"

    LC_ALL=C awk -v B="$MARKER_BEGIN" -v E="$MARKER_END" '
        index($0, B) > 0 { inblock=1 }
        inblock { print }
        inblock && index($0, E) > 0 { exit }
    ' "$f" > "$cur"

    if diff -q "$cur" "$blk" >/dev/null 2>&1; then
        rm -f "$blk" "$cur"
        trap - EXIT INT TERM
        printf 'ℹ️  區塊已是現行版本，未改動: %s\n' "$f"
        return 0
    fi

    LC_ALL=C awk -v B="$MARKER_BEGIN" -v E="$MARKER_END" -v blk="$blk" '
        index($0, B) > 0 {
            while ((getline line < blk) > 0) print line
            close(blk)
            inblock = 1
            next
        }
        inblock { if (index($0, E) > 0) inblock = 0; next }
        { print }
    ' "$f" > "$tmp"

    # 用 cat 寫回而不是 mv：目標是 symlink 時 mv 會把它換成實體檔，也會換掉原檔的權限。
    cp "$f" "$f.bak-$TS"
    cat "$tmp" > "$f"
    rm -f "$blk" "$cur" "$tmp"
    trap - EXIT INT TERM

    printf '✅ 已更新施工筆記區塊: %s（備份 .bak-%s）\n' "$f" "$TS"
}

inject_file() {
    f="$1"

    # 不存在則略過，不建立（避免憑空產生空檔污染專案）
    if [ ! -f "$f" ]; then
        printf '⚠️  檔案不存在，已略過（不建立）: %s\n' "$f"
        return 0
    fi

    if grep -qF "$MARKER_BEGIN" "$f"; then
        # 存回原值：目錄模式下每個檔案各自繼承，不要被前一個檔案帶壞
        saved_display="$SCRIPTS_DISPLAY"
        inherit_scripts_path "$f"
        refresh_file "$f"
        SCRIPTS_DISPLAY="$saved_display"
        return 0
    fi

    blk="$f.wnblock.$$"
    tmp="$f.wninject.$$"
    trap 'rm -f "$blk" "$tmp"' EXIT INT TERM
    make_block > "$blk"

    if [ -n "$ANCHOR" ] && grep -qF "$ANCHOR" "$f"; then
        LC_ALL=C awk -v A="$ANCHOR" -v blk="$blk" '
            { print }
            !inserted && index($0, A) > 0 {
                print ""
                while ((getline line < blk) > 0) print line
                close(blk)
                inserted = 1
            }
        ' "$f" > "$tmp"
        where="指定標記之後"
    else
        # 檔頭。原檔有內容才補一行空白隔開。
        cp "$blk" "$tmp"
        if [ -s "$f" ]; then
            printf '\n' >> "$tmp"
            cat "$f" >> "$tmp"
        fi
        where="檔案開頭"
    fi

    cp "$f" "$f.bak-$TS"
    cat "$tmp" > "$f"
    rm -f "$blk" "$tmp"
    trap - EXIT INT TERM

    printf '✅ 已注入施工筆記指引: %s（位置：%s，備份 .bak-%s）\n' "$f" "$where" "$TS"
    printf '    規則段裡的腳本路徑：%s\n' "$SCRIPTS_DISPLAY"
}

if [ -d "$TARGET" ]; then
    inject_file "$TARGET/AGENTS.md"
    inject_file "$TARGET/CLAUDE.md"
    inject_file "$TARGET/GEMINI.md"
else
    case "$TARGET" in
        *.md) inject_file "$TARGET" ;;
        *) printf '❌ 目標必須是目錄或 .md 檔: %s\n' "$TARGET" >&2; exit 1 ;;
    esac
fi

printf '\nskill 套件複製到規則段所指位置的動作不由本腳本負責。\n'
