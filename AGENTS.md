# AGENTS.md — 給幫使用者把 Talky 接好的 AI（Claude Code、Codex、Cursor、任何 agent）

你正在幫一個人把 **Talky**（macOS 繁體中文語音輸入法，開源）在他的 Mac 上接好。
目標只有一個：**他在任何文字框連按兩下右 ⌘、講一句話，整理好的繁中貼進游標處。**
**驗收＝這件事真的發生**（§6），不是「某顆大腦測試通過」。全程不要動他的其他設定、不要刪東西、不要幫他填 API 金鑰。

這份檔隨 app 一起裝在 `/Applications/Talky.app/Contents/Resources/AGENTS.md`，沒有原始碼倉也讀得到；不要上網找 repo。

## 0. 第一件事：跑體檢（不要自己 ls 猜）

```bash
/Applications/Talky.app/Contents/MacOS/Talky --doctor
```

一次看完：麥克風／輔助使用／語音模型／Claude Code／ChatGPT（Codex）／整理模式／引擎／**Talky 在不在跑／快捷鍵有沒有在聽／Hearby 有沒有在搶鍵**。
每一行「缺」對應下面一節：權限 → §2、大腦 → §3、Hearby → §5。app 沒裝 → §1。
其他要看的：`uname -m` 要是 arm64（x86_64 不支援，直接停）、`sw_vers -productVersion` 要 14 以上、`df -g ~` 剩餘要夠（語音模型 1.5GB；內建整理模型再 2.5GB）。

## 1. 裝 app

- 有 `Talky-*.dmg`：掛載後直接雙擊裡面的 `Talky.app`——0.1.8 起它會自己複製到 `/Applications`、釘進 Dock、從那裡重開並退出映像；或照舊拖（`ditto`）進 `/Applications` 再從那裡打開。
- 只有原始碼：`bash scripts/vendor-fetch.sh && bash build.sh && open build/Talky.app`（要先 `xcode-select --install`）。
- 或 `bash scripts/setup.sh`：自動做 app、Claude Code、ChatGPT 桌面版、Ollama 這幾件。

打開後 app 會跑五步精靈（0.1.2）：麥克風 → 輔助使用 → 整理方式（app 已替他選好）→ 試講一句 → 好了。每一步都寫了「你要做的事 1-2-3」，可以陪他走；也可以先把大腦接好（§3）再讓他走。

## 2. 兩個權限：只有他本人能按，AI 做不到，要陪他做

| 權限 | 是否必要 | 怎麼開 |
|---|---|---|
| **麥克風** | 必要 | 第一次口述系統會問 → 按「允許」。拒絕過：系統設定 → 隱私權與安全性 → 麥克風 → Talky 打開 |
| **輔助使用** | **必要——沒開，連按右 ⌘ 完全不會有反應**（熱鍵監聽根本不會掛） | 系統設定 → 隱私權與安全性 → 輔助使用 → 找到 Talky → 開關打開（可能要輸入 Mac 密碼）。精靈第 2 步「去開啟」會直接跳到那頁 |

- 開完之後 app 會在 2 秒內自己把快捷鍵接上（0.1.1 起；0.1.0 要「結束 Talky」再從應用程式打開一次）。
- 系統設定裡開著、`--doctor` 卻說未授權：多半是 app 更新過、系統記的是舊簽名。跑 `tccutil reset Accessibility ltd.intention.talky`，再開一次 app 重新給；精靈第 2 步也有這顆「清掉舊記錄再開一次」。
- `--doctor` 說「快捷鍵沒接上」：這台 macOS 另外要「輸入監控」→ 系統設定 → 隱私權與安全性 → 輸入監控 → Talky 打開。
- 沒開輔助使用的唯一退路＝點 Dock 圖示 → 狀態視窗 → 「試講一句」，字會進剪貼簿。這不是正常使用方式，別停在這裡。

## 3. 接「整理大腦」：優先用他已經有的訂閱額度，不用 API 金鑰

順序照這個，接到一顆能用就停：

| 順位 | 條件 | 怎麼接 | 怎麼驗 |
|---|---|---|---|
| 1 | 他有 Claude 訂閱（Pro／Max） | 沒裝：Talky 設定 → 進階 → Claude 那列按「安裝」，app 自己跑官方腳本（不開終端機、不需 Node／sudo），裝好自動接登入。終端機版：`curl -fsSL https://claude.ai/install.sh \| bash`。**沒登入（最常見：Claude 桌面版登入了，但命令列這顆沒有——桌面版的 token 只活在它自己的子行程環境變數裡，借不到）**：那列按「登入」——Talky 自己開瀏覽器，他登入按允許；網頁若給一串代碼，貼回 Talky 那格按「送出」；接上會自動打勾。終端機版：`claude auth login` | `claude auth status` 印出 `"loggedIn": true` |
| 2 | 他有 ChatGPT 訂閱（Plus／Pro） | Talky 設定 → 進階 → ChatGPT 那列按「接上 ChatGPT」：app 自己下載官方 Codex 獨立執行檔（90MB，不需 Node、不需 ChatGPT 桌面版）到 `~/Library/Application Support/Talky/bin/codex`，裝好自動開瀏覽器登入，登入完自動綁定。已有 ChatGPT 桌面版的機器會直接用它自帶的 codex。**已登入的機器千萬別再跑 `codex login`（會先清掉現有登入）** | `codex login status` 印出 Logged in |
| 3 | 兩者都沒有、記憶體 ≥12GB | 精靈已自動選「不用帳號：內建模型」並在聽寫模型之後自動下載 2.5GB；手動＝設定 → 進階 那列按「下載」 | 那列按「測試」有回一句 |
| 4 | 想用 Ollama | 設定 → 進階 →「更多選項」→ Ollama；裝 Ollama、`ollama pull qwen3:4b` | 同上 |
| 5 | 都不要 | 「更多選項」→「不整理」——字照樣貼，只做繁體化與標點（記憶體 <12GB 的機器精靈會自動選這個） | — |

裝了 Claude Code 但沒登入（`--doctor` 會寫「未登入」）：登入只能他本人在瀏覽器按，但**不用開終端機**——陪他按 Talky 那顆「登入」就好。他不想弄才走順位 2。
整理模型預設 **Opus**（`claudeModel` 預設 `opus`＝他帳號最新的 Opus；要省時間可 `defaults write ltd.intention.talky claudeModel sonnet`）。
API 金鑰（OpenAI 相容端點／Anthropic）收在設定 → 進階「進階：用 API 金鑰」，**除非他明說要用金鑰，不要幫他選這條**。

## 4. 選用並驗證

```bash
# 選大腦（也可以在 設定 → 進階 點那一整列）：claudeCLI｜codex｜local｜ollama｜off
defaults write ltd.intention.talky polishMode codex
# 真跑一句整理（不收音）
/Applications/Talky.app/Contents/MacOS/Talky --ime-polish "呃就是那個我們明天下午三點要開會嘛,啊不對是四點"
```

`--ime-polish` 要印 `OK <秒數> path=<claude|codex|local|ollama>` 加一句整理過的話。`path=raw` 代表大腦沒接上，回去看 §3 的驗證欄。

## 5. 同一台有 Hearby（同一家的會議記錄 app）

- 語音模型會直接借用 Hearby 已下載的那份，不用再下載。
- Hearby 舊版也聽右 ⌘，兩邊會搶（`--doctor` 會寫出來）。精靈第 4 步與狀態視窗都有一顆「關掉它的輸入法」（只關輸入法，會議功能不動）。手動版：`defaults write ltd.intention.werehear imeMode -bool false`。

## 6. 最後驗收（一定要做，做完才算接好）

1. 再跑一次 `--doctor`：麥克風 ok、輔助使用 ok、語音模型 ok、Talky 在跑、**快捷鍵：在聽**、選的大腦已登入。
2. 請他打開「備忘錄」，把游標放進去，**連按兩下空白鍵右邊那顆 ⌘**（像滑鼠雙擊那麼快）→ 螢幕下方要出現面板 → 講「今天天氣不錯」→ 再按一次 → 字貼進備忘錄。
3. 沒出面板 → 回 §2（十之八九是輔助使用）；出面板但貼的是原稿、面板寫「未整理」→ 回 §3；面板寫「語音模型還沒下載完」→ 精靈收尾頁「語音模型」那列的「下載」，或狀態視窗那顆「下載」。
4. 把 `--doctor` 的輸出貼給他看，結束。

## 7. 不要做的事

- 不要幫他填任何 API 金鑰，除非他明說。
- 不要 `rm` 任何東西；要換掉的檔案用 `mv` 搬走。
- 不要改他的 Hearby 設定（除了 §5 那一個開關）。
- 不要把逐字稿、記錄檔貼到任何外部服務；出問題請他用 設定 → 一般 →「匯出診斷檔到桌面」，那份檔不含金鑰。

## 8. 檔案在哪

| 什麼 | 路徑 |
|---|---|
| 這份檔 | `/Applications/Talky.app/Contents/Resources/AGENTS.md` |
| 設定 | `defaults read ltd.intention.talky` |
| 記錄檔 | `~/Library/Logs/Talky/talky.log` |
| 模型、常用詞 | `~/Library/Application Support/Talky/`（有 Hearby 時借用 `~/Library/Application Support/WereHear/`） |
| 引擎 port | 語音 `127.0.0.1:8932`、本機整理 `127.0.0.1:8947`（只綁 localhost） |
