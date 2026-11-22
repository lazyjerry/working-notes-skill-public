# working-notes-skill

以「一任務一份筆記 + 一份可掃的索引」累積**每個專案自己的**施工結論，讓後續任務不必從頭摸索。

機制是全域的（一套規則、一套腳本，跨 AI 工具共用），筆記本身留在各專案內、依專案分開。

GitHub：<https://github.com/lazyjerry/working-notes-skill-public>

## 安裝

兩條路擇一：**用 ai-global 安裝**（一個指令，自動同步到所有 AI 工具），或**手動安裝**（clone、複製、注入規則段）。要交給 AI 代理代勞，直接用下面的〈用 AI 安裝〉。

### 用 AI 安裝

不想自己逐步操作，可以把下面這段貼給 Claude Code、Codex 這類能執行指令的 AI 代理。它會照這份文件檢查需求、問清楚選項，再呼叫後面幾節寫的指令與腳本；安裝動作仍只有那些指令與腳本一份。

```text
請幫我安裝 working-notes-skill（https://github.com/lazyjerry/working-notes-skill-public）。

1. 取得來源：把 repo clone 到 ~/working-notes-skill；已經存在就在裡面 git pull。

2. 讀文件、檢查需求：讀 repo 的 README.md「安裝」整章，一切以它為準，不要憑印象安裝。
   逐項檢查「需求」：git、bash 3.2 以上、作業系統。
   缺任何一項就停下來，告訴我缺什麼、怎麼補，不要自行安裝或略過。

3. 先問我這幾件事，問完再動手：
   - 安裝方式：`command -v ai-global` 有結果就預設「用 ai-global 安裝」，沒有就走「手動安裝」；
     用哪一種先跟我確認。
   - 走手動安裝時，skill 本體要就地使用（A）還是複製到 AI 工具的 skills 目錄（B）；
     選 B 再問是哪個工具的目錄。
   - 要不要注入規則段；要的話注入哪一份指令檔。
     不帶參數執行 `sh scripts/wn-install.sh` 會列出偵測到的候選後結束（結束碼非 0 是正常的），
     把清單給我挑，不要替我選。

4. 只用 README 寫的指令與 repo 內的腳本安裝：
   `ai-global add-skill`、`cp -R`、`scripts/wn-install.sh` 與它的 `--skill-dir`／`--after` 參數。
   已經裝過就改照 README 的「更新」段落做。
   不要修改 repo 內的任何檔案，不要手動編輯我的指令檔；目標指令檔不存在時不要替我建立。

5. 驗證並回報，只用唯讀指令：
   - skill 本體：`ls <skill 目錄>/SKILL.md`；
     用 ai-global 安裝時另加 `ai-global list-skills | grep working-notes-skill`。
   - 規則段（有注入才查）：`grep -n 'working-notes-skill:notes' <指令檔>`。
   回報：用了哪種安裝方式、skill 目錄的位置、規則段注入到哪一份檔案與裡面寫的腳本路徑、
   備份檔（.bak-<時間戳>）的位置。
   README「驗證」的冒煙測試會在專案裡建檔，不要自己跑，把指令告訴我就好。
```

更新時同一段提示詞再貼一次：來源已存在會改成 `git pull`，已經裝過會改走「更新」段落。

### 需求

- `git`、`bash` 3.2 以上（macOS 內建即可）
- macOS 或 Linux；Windows 需 WSL 或 Git Bash

### 用 ai-global 安裝

[ai-global](https://github.com/lazyjerry/ai-global) 把 `~/.ai-global/` 當中央目錄，再 symlink 到各家 AI 工具（Claude Code、Codex、Cursor、Copilot、Gemini、OpenCode…）。skill 裝一次，所有工具同時看得到。

```bash
ai-global add-skill lazyjerry/working-notes-skill-public
```

它會 clone 整個 repo、掃到 `skills/working-notes-skill/SKILL.md`，把那個目錄裝進 `~/.ai-global/skills/working-notes-skill/`，並把來源記進 `~/.ai-global/source.md`。symlink 既有就直接生效，不必再 `relink`。

驗證：

```bash
ai-global list-skills | grep working-notes-skill
cd <任一專案> && bash ~/.ai-global/skills/working-notes-skill/scripts/wn-new.sh "冒煙測試"
```

#### 規則段（選用）

`SKILL.md` 會被工具自動載入，但要模型判斷相關才會用。想讓「動工前掃索引、收尾寫筆記」**每次任務**都生效，才需要注入規則段。

`wn-install.sh` 是一次性工具、不隨 skill 出貨，所以得另外 clone 一份 repo：

```bash
git clone https://github.com/lazyjerry/working-notes-skill-public.git /tmp/wn
sh /tmp/wn/scripts/wn-install.sh ~/.ai-global/AGENTS.md \
   --skill-dir ~/.ai-global/skills/working-notes-skill
```

目標給 `~/.ai-global/AGENTS.md`。`~/.claude/CLAUDE.md` 這類在 ai-global 底下是指向它的 symlink，給哪一個改到的都是同一份實體檔——`wn-install.sh` 是把內容寫回原檔，不會把 symlink 換成實體檔。`~/.ai-global/AGENTS.md` 只在初次建立時合併一次，之後 `ai-global update` 不會重寫它，直接注入是安全的。

#### 更新與移除

```bash
ai-global update-skills                                       # 依 source.md 重裝所有 skill
ai-global remove-skill working-notes-skill                    # 移除 skill 與安裝紀錄
sh /tmp/wn/scripts/wn-uninstall.sh ~/.ai-global/AGENTS.md     # 有裝規則段才需要
```

### 手動安裝

沒用 ai-global，或想自己控制放哪裡時走這條。

#### 1. 取得

```bash
git clone git@github.com:lazyjerry/working-notes-skill-public.git ~/working-notes-skill
```

用 HTTPS：`git clone https://github.com/lazyjerry/working-notes-skill-public.git ~/working-notes-skill`

放哪裡都可以，clone 下來的位置就能直接用。以下路徑以 `~/working-notes-skill` 為例。

#### 2. 部署 skill 本體

兩種擇一。

**A. 就地使用**——不複製，直接用 clone 的位置。步驟最少，適合只要腳本、靠指令檔規則段驅動的情況。

**B. 複製到 AI 工具的 skills 目錄**——讓工具自己載入 `SKILL.md`。以 Claude Code 為例：

```bash
mkdir -p ~/.claude/skills
cp -R ~/working-notes-skill/skills/working-notes-skill ~/.claude/skills/
```

其他工具依各自的 skills 佈署位置放。**複製動作不由本 repo 的腳本負責**，那是各家工具自己的佈署機制。

#### 3. 注入規則段到 AI 指令檔

把「動工前掃索引、收尾寫筆記」寫進指令檔，每次任務才會生效：

```bash
# 方式 A（就地使用）
sh ~/working-notes-skill/scripts/wn-install.sh ~/.claude/CLAUDE.md

# 方式 B（已複製到 ~/.claude/skills）
sh ~/working-notes-skill/scripts/wn-install.sh ~/.claude/CLAUDE.md \
   --skill-dir ~/.claude/skills/working-notes-skill
```

- 不給目標路徑會列出偵測到的候選（`~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.gemini/GEMINI.md`、`~/.ai-global/AGENTS.md`）並結束——猜使用者用哪套工具只會裝錯地方。
- 目標給目錄則注入其下的 `AGENTS.md`／`CLAUDE.md`／`GEMINI.md`；**檔案不存在不會建立**，不會憑空產生空檔。
- `--skill-dir <路徑>` 決定規則段裡寫出來的腳本路徑，預設是本 repo 的 `skills/working-notes-skill`。家目錄前綴會寫回 `~`，不會寫死使用者名稱。
- **目標檔已經有區塊時，沒明講 `--skill-dir` 就沿用它裡面現有的路徑。** 重跑通常是為了更新規則文字而不是換腳本位置；沒有這條的話，「從 repo 重跑一次升級措辭」會靜默把全域設定的路徑從佈署位置改指回 repo，而且看起來一切正常。
- `--after "<標記字串>"` 指定插在含該字串的那行之後；沒給或找不到就插在**檔案開頭**。開頭是預設值：這是「動工前先做什麼」的規則，擺在檔尾等於排在一堆其他指引後面才被讀到，指令檔越長越明顯。

規則段用標記區塊 `<!-- BEGIN working-notes-skill:notes -->` 包住自己的內容，區塊外一個字不動；改檔前留 `.bak-<時間戳>`。重跑會就地更新區塊（冪等）。

#### 4. 驗證

```bash
cd <任一專案>
bash ~/.claude/skills/working-notes-skill/scripts/wn-new.sh "冒煙測試"
```

它會印出建好的檔案路徑，順帶建出 `docs/working-notes-skill/`。確認無誤後把那個檔案與資料夾刪掉即可。**腳本一律用 `bash` 呼叫，不能用 `sh`**（原因見文末）。

#### 更新

```bash
cd ~/working-notes-skill && git pull

# 方式 B 才需要重新複製（先刪再複製，避免留下舊檔）
rm -rf ~/.claude/skills/working-notes-skill
cp -R skills/working-notes-skill ~/.claude/skills/

# 規則段內容有變更時重跑，會就地更新區塊
sh scripts/wn-install.sh ~/.claude/CLAUDE.md --skill-dir ~/.claude/skills/working-notes-skill
```

#### 移除

```bash
sh ~/working-notes-skill/scripts/wn-uninstall.sh ~/.claude/CLAUDE.md
rm -rf ~/.claude/skills/working-notes-skill    # 方式 B 才需要
```

只拆掉標記區塊，區塊外的內容一個字不動；對沒安裝的狀態執行不報錯。

**不刪任何專案的筆記**——那是使用者累積的施工紀錄，解除規則掛載不該順手清掉，所以沒有 `--purge`。

## 這套機制在做什麼

1. **索引先掃**——`index.md` 只有標題與一句摘要，一份掃得完，命中才開該筆記，不整批讀。過時筆記另列在 `obsolete.md`，不必讀。
2. **一任務一檔**——`YYYY-MM_NN_主題.md`，`NN` 是**工作階段序號不是日期**（同階段共用、開新階段才 +1）。
3. **索引由腳本重建**——從每份筆記的 H1 與第一段抽標題／摘要，不手動編輯。
4. **計畫檔留檔**——進出 Plan Mode 各存一次，同名覆寫。
5. **ADR 優先**——專案有 `docs/adr/`、`docs/decisions/` 或 `.agents/adr/` 時，`wn-reindex.sh` 在 `index.md` 底部另列 ADR 表，`wn-new.sh` 建檔後也會提醒。ADR 多半進版控、團隊共享，筆記多半只在本機，同一個決策以 ADR 為準，筆記只寫一句指向它。這條只適用**進了版控**的 ADR：沒進版控的在表上標「（未進版控）」，份量跟筆記一樣。ADR 目錄自帶索引時（第一層的 `README.md`／`index.md`，內文提到該目錄的 ADR 檔名），表上只放一列指向它，裡面列到且進了版控的 ADR 不逐份重列。

## 目錄

```
skills/working-notes-skill/     出貨內容，每次任務都會呼叫
├─ SKILL.md
├─ agents/openai.yaml           Codex 的介面設定與自動觸發開關
├─ assets/
│  ├─ note-template.md          新筆記的骨架
│  ├─ gitignore-untracked       預設：筆記不進版控
│  └─ gitignore-tracked         切換用：筆記進版控
└─ scripts/
   ├─ wn-common.sh              專案根解析與共用函式（其餘各支 source 它）
   ├─ wn-new.sh      【寫】     建立一份新筆記
   ├─ wn-reindex.sh  【寫】     重建本專案的 index.md
   ├─ wn-plan.sh     【寫】     留存 Plan Mode 的計畫檔
   ├─ wn-obsolete.sh 【寫】     標記／取消過時，並重建索引
   └─ wn-vcs.sh                 查／切換筆記要不要進版控

scripts/                        一次性工具，不隨 skill 出貨
├─ wn-install.sh                把規則段注入 AI 指令檔
├─ wn-uninstall.sh              移除規則段
└─ wn-adopt.sh                  把專案既有的筆記目錄改名到標準路徑
```

分家的判準是**呼叫頻率**：`skills/` 內是每次任務都跑的，`scripts/` 內是一輩子跑一兩次的。裝機與遷移工具塞進 skill 只會讓模型每次讀 SKILL.md 都看到用不到的東西。

## 筆記存在哪

```
<專案根>/docs/working-notes-skill/
├─ .gitignore      首次建目錄時佈署，由 wn-vcs.sh 切換，預設不進版控
├─ notes/          施工筆記、index.md 與 obsolete.md
└─ plans/          Plan Mode 的計畫檔
```

專案根由腳本自己解析：git 根目錄，失敗則往上找 `.git`／`CLAUDE.md`／`AGENTS.md`／`package.json`／`composer.json`，都沒有才用目前工作目錄。

**路徑固定，沒有設定可調。** 曾經有個 `WORKING_NOTES_DIR` 環境變數，是筆記還集中在家目錄那版設計的殘留——那時「換台機器想放別的磁碟」才需要覆寫。改成筆記留在專案內之後，路徑變成「專案根 + 固定相對路徑」，那個理由就沒了，而它是唯一能讓路徑跑掉的東西：光是擋住 `.`、`..` 與「指到專案根導致 `.gitignore` 忽略整個 repo」就要三道防護。拿掉之後，唯一的失效模式是專案根解析錯了，而寫入類的腳本都會把解析到的路徑印出來。

## 用法

### 日常（由 AI 代理自己呼叫）

```bash
bash skills/working-notes-skill/scripts/wn-new.sh "主題"       # 收尾建檔
bash skills/working-notes-skill/scripts/wn-new.sh "主題" --new-stage  # 開新的工作階段（序號 +1）
bash skills/working-notes-skill/scripts/wn-reindex.sh         # 寫完重建索引
bash skills/working-notes-skill/scripts/wn-plan.sh <計畫檔>    # 進出 Plan Mode 各一次
bash skills/working-notes-skill/scripts/wn-obsolete.sh <筆記> "以此為準"  # 整份被取代時標過時（--clear 取消）
bash skills/working-notes-skill/scripts/wn-vcs.sh             # 查／切換版控狀態
```

刪除筆記：`rm` 該檔後跑 `wn-reindex.sh`，不另開腳本。整份被規範或新筆記取代的筆記用 `wn-obsolete.sh` 標過時，不直接刪：它會從 `index.md` 移到 `obsolete.md`，當時的脈絡還查得到。

**讀取沒有腳本**：動工前直接讀 `<專案根>/docs/working-notes-skill/notes/index.md`。路徑固定、內容就是一份 markdown，包一層腳本只是多一個呼叫。而且查詢動作不該有寫入副作用——早期版本有支 `wn-status.sh` 會順手建目錄，等於代理光是看一眼，就在每個路過的 repo 種下一個空的 `docs/working-notes-skill/`。現在只有 `wn-new.sh` 與 `wn-plan.sh` 會建目錄，其餘腳本碰到目錄不存在就回報「還沒有筆記」並結束。

**第一次建目錄要告知使用者**：`wn-new.sh`／`wn-plan.sh` 第一次建立 `notes/` 並佈署 `.gitignore` 時，會在 stderr 印出 `已建立筆記目錄：…`、`已佈署 .gitignore：…`。stderr 只有代理看得到，所以 `SKILL.md` 規定代理看到這兩行就要在回覆裡講清楚：建在哪個資料夾（專案根相對路徑，加上解析到的專案根）、建了 `.gitignore` 而筆記預設不進版控、要進版控用 `wn-vcs.sh tracked`。專案根找不到標記檔時會退回目前工作目錄，當下講出來，落點錯了才看得出來。

### 檔名規則

筆記是 `notes/YYYY-MM_NN_主題.md`，計畫是 `plans/<H1 標題>.md`，主題與標題共用同一套轉換（`wn-common.sh` 的 `wn_slug`）：中文字原樣保留，空白與 `/ : ? * " < > | \ ( ) [ ] { }` 及全形括號、引號、`：？！、，。；｜` 換成 `-`，連續的 `-` 收成一個、頭尾去掉。

例：`# 範例功能 v2 改版計畫（第二版）` → `plans/範例功能-v2-改版計畫-第二版.md`。

半形符號用 `tr`（兩邊都是 ASCII，不會誤傷 UTF-8 續接位元組），**全形符號一定走 `sed` 的字面取代**——`tr` 是逐位元組運作的，把多位元組字元塞進字元集會拆散它、產生無效 UTF-8。

### 版控

預設不進版控。切換走腳本，不要手動編 `.gitignore`：

```bash
bash skills/working-notes-skill/scripts/wn-vcs.sh tracked     # 筆記跟著 repo 走
bash skills/working-notes-skill/scripts/wn-vcs.sh untracked   # 只存在本機（預設）
```

`tracked` 模式仍排除 `backup-*/` 與 `.gitignore.bak-*`，那些是一次性產物。`.gitignore` 被手動改過時腳本拒絕覆寫，要 `--force`。

切 `tracked` 前先確認筆記內容——筆記寫的是內部取捨與踩過的坑，進版控就會被推上遠端。切回 `untracked` 不會讓已經提交過的紀錄消失，腳本會把 `git rm -r --cached` 指令印出來。

### 把既有的筆記目錄併進來

專案原本已有自己的筆記目錄（例如 `docs/notes/`）時：

```bash
bash scripts/wn-adopt.sh                                   # dry-run，什麼都不改
bash scripts/wn-adopt.sh --from docs/notes --yes            # 搬檔 + 重建索引
bash scripts/wn-adopt.sh --from docs/notes --yes \
     --rewrite-refs --skip-refs 'docs/plans/*' --skip-refs 'scripts/one-time/*'
```

不給 `--from` 時依序找 `docs/notes`、`notes`、`docs/working-notes`、`working-knowledge`，取第一個含 `.md` 的目錄。

**引用改寫預設不做，要 `--rewrite-refs` 才會動。** 專案裡指向筆記目錄的檔案，往往有一大半是執行後的計畫存檔、研究報告與一次性腳本——那些是當時的紀錄，改它們等於竄改歷史。哪些該改只有人知道，所以預設只列出來。

筆記彼此的同目錄相對連結（`[標題](2026-08_01_xxx.md)`）搬完仍然有效，不必處理。跨出目錄的相對連結（`](../../foo.md)`）會因為深度變了而失準，這類由腳本自動補上層數。

搬檔前會整份備份到 `<專案根>/docs/working-notes-skill/backup-<時間戳>/`（在 `.gitignore` 涵蓋範圍內）；加了 `--rewrite-refs` 時，被改寫的檔案原樣存在其下的 `refs-orig/<原相對路徑>`。核對無誤後自行刪除。

## 為什麼 skill 腳本是 bash 不是 POSIX sh

skill 腳本用到 POSIX sh 沒有的東西：`local`、`${var//a/b}` 字串取代、`${s:i:1}` 取子字串、`$'\n'`、`set -o pipefail`、`BASH_SOURCE`。

索引摘要截斷到 70 字就靠 `${s:i:1}`（`wn-reindex.sh` 的 `truncate_utf8`）：固定在 C locale 逐位元組走，只數 UTF-8 的起始位元組，截斷點必落在字元邊界，結果與呼叫端的 locale 無關。不直接用 `${#var}`／`${var:0:70}`，因為它們依 `LC_CTYPE` 計算，在 `LANG` 為空的環境（AI CLI、cron）會以位元組計，把中文切在字元中間，索引變成非法 UTF-8。

所以 `skills/` 底下用 `#!/usr/bin/env bash`，**呼叫時要用 `bash` 不能用 `sh`**（macOS 的 `/bin/sh` 剛好是 bash 3.2 所以看不出來，Linux 上就會壞）。`scripts/` 底下的 `wn-install.sh` 與 `wn-uninstall.sh` 沒有這個需求，維持 POSIX `sh`；`wn-adopt.sh` 要 source `wn-common.sh`，同樣是 bash。

## 中文安全

筆記檔名、標題、摘要全是中文，兩個已知的坑都在路徑上：

- macOS 的 `en_US.UTF-8` 對 CJK 沒有 collation 權重，`awk` 的 `==` 對純中文字串一律回真，`sort -u` 會靜默吃掉不同的中文行。所以比較與排序一律加 `LC_ALL=C`。
- macOS 內建的 `/bin/sh`（bash 3.2.57）執行 `echo "$VAR全形字"` 會遺失一個位元組。所以輸出一律 `printf`，不用 `echo`。

## 與其他機制的關係

本 skill 不依賴、也不假設任何其他 skill 或套件存在。

`wn-install.sh` / `wn-uninstall.sh` 在沒給目標時會探測幾個常見的 AI 指令檔位置（`~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.gemini/GEMINI.md`、`~/.ai-global/AGENTS.md`）**列給使用者挑**，只是省去打字，功能不依賴其中任何一個存在。

施工筆記收的是**這個專案**的結論。換到別的專案仍然成立的通則不屬於這裡——寫進專案筆記等於把它鎖在一個專案裡。若環境另有跨專案的知識庫機制，通則歸它，兩邊各寫完整一份、不互相連結。

## 授權

[MIT](LICENSE)
