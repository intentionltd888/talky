# Talky iPhone 版

一句話：**在任何 App 的輸入框切到 Talky 鍵盤、講話，整理好的繁中直接打進去；長按圓鈕往上滑，就翻成泰文／日文／英文，語氣照對象（客戶、朋友、女生朋友…）。**（像 Typeless／Wispr Flow 的 iPhone 鍵盤）

辨識在手機上（iOS 內建 Apple 語音模型，免下載）。整理兩種：**Claude 訂閱**（請你的 Mac mini 用登入好的 Claude Code 代跑，不用 API 金鑰）或 **Apple**（手機本機，免費離線）。整個 app 5 MB。

## 裝到手機

第一次（只有本人能做，約 3 分鐘）：

1. iPhone 用線接上 Mac → 解鎖 → 按「信任這部電腦」
2. Xcode → Settings → Accounts → ＋ 登入 Apple ID（開發者帳號 CP6J9DCLQL）
3. iPhone：設定 → 隱私權與安全性 → 開發者模式 → 打開（會重開機）

然後：

```bash
bash ios/install.sh
```

裝好後在手機上：Talky 首頁「設定鍵盤」三步（麥克風 → 加入鍵盤 → 允許完整取用），在任何輸入框長按 🌐 切到 Talky。

## 怎麼運作（怎麼做到不跳 app）

iOS 規定**鍵盤擴充不能開麥克風**（Typeless、Wispr Flow 也一樣），所以收音在主 app。做法是「待命」：主 app 先把麥克風開好，鍵盤在原地叫它聽。

1. **開待命（不用跳）**：按**動作按鈕**或**控制中心**的「Talky 待命」（設定 → 動作按鈕 → 控制項 → Talky 待命），系統在背景把 Talky 叫起來開麥克風，你人還在原本的 App；動態島出現米字＋「待命」。打開 Talky 本身也會自動待命。
2. **在任何 App 講**：切到 Talky 鍵盤 → **點一下**圓鈕開始講 → **再點一下** → 整理好的字打進游標（可按「復原」「原文」）。動態島同步顯示「聽／整理」。
3. **待命預設不關**：之後一整天都在原地講；來電講完會自己接回麥克風。只有重開機或按「結束待命」才會關。
4. 沒在待命時按鍵盤圓鈕，會退回舊辦法：跳到 Talky 開麥克風，點左上角「◀」回去。

## 翻譯（照 Typeless 的用法，多一層「對象」）

1. **設定**：首頁「翻譯目標」排好最多 4 個，每個＝語言＋對象（預設：泰文・女生朋友、日文・客戶、英文・客戶）。「我的口吻」選男生／女生（泰文 ครับ／ค่ะ、日文口語 僕／私；不指定＝中性說法）。
2. **鍵盤**：點一下圓鈕＝講中文；**長按圓鈕往上滑**＝最上面排開翻譯目標，停在哪個（凹下去）放開就開始講，這一句翻成它。每句現場挑，不會卡在翻譯模式。
3. **打上之後**：狀態列顯示「意思：…」（譯文直譯回中文，確認語氣）；左邊「復原」「中文」（換回中文）。
4. **誰翻**：Claude 訂閱（配對的 Mac，或自架整理服務的 `/api/talky/polish` 帶 `mode=translate`；情境說明從手機送、各語言規則與口吻在服務那邊，跟 Mac 版 `Translate.swift` 同一份；句尾只看口吻、語氣只看對象）。都連不到 → Apple 離線翻譯（首頁「離線翻譯」先下載語言；只有意思沒有語氣）→ 都不行就給中文但**不自動打**（按「貼上」才打），免得中文誤傳給外國客戶。
5. 對象（朋友／同事／客戶）怎麼影響語氣與稱呼：規則在 `Shared/Translate.swift`。

## 用你自己的 Claude／ChatGPT 訂閱（經由你的 Mac）

Anthropic 不准第三方 app 直接登入 Claude 訂閱（[官方條款](https://code.claude.com/docs/en/legal-and-compliance)，2026），ChatGPT 也沒開放給第三方用訂閱。合規的路＝**你自己的 Mac** 上跑官方、沒改過的 Claude Code／Codex，用你的帳號在 Mac 上登入；iPhone 只把一句話加密送過去。

1. Mac 版 Talky → 設定 →「iPhone（用這台 Mac 的訂閱整理與翻譯）」→ 打開（預設關）。
2. 用 iPhone 相機掃畫面上的 QR 碼 → 自動打開 Talky 配對好（`talky://pair?…`）。
3. iPhone Talky →「整理方式」→ 看得到 Mac 上 Claude／ChatGPT 登入了沒、要用哪一顆；沒登入按「在 Mac 上登入」，Mac 會打開官方登入頁。

安全：Mac 只在打開時聽 47810 埠、只接私有網段／Tailscale；每個請求用配對金鑰加密＋驗證（ChaCha20-Poly1305，擋重放），金鑰只在 QR 碼出現一次、存鑰匙圈。
順序：配對的 Mac → 自架的整理服務（選用）→ Apple。協定兩邊同一份：Mac `app/Sources/RelayCore.swift`、iPhone `App/MacRelay.swift`。
自架的整理服務（選用，給有一台常開的機器、跑同一套 `/api/talky/polish` 的人）：把位址寫在 `~/.config/talky/ios-bridge-url`（一行，不進倉），`bash ios/install.sh` 編譯時會帶進去；沒有這個檔就跳過這一步。

## 長相（Talky 的設計規則＋原生鍵盤灰）

跟 Mac 版同一套（`app/Sources/Neu.swift`、`3_介面/全介面 候選 0907`）：一塊材料，凸起＝可按、凹陷＝容器或已選；主行動鈕＝錨圓鈕（圓點＝開始、方塊＝講完）；米字光點是唯一會自己動的東西；不用藍、不用黑。
iPhone 版只換材料色＝原生鍵盤的灰（淺色 #DEDFE4、深色 #1E1F23，iOS 26 實測），切到 Talky 鍵盤不會跳色。
鍵盤排版＝L1「儀器面板」：上面凹顯示窗、中間三顆圓鈕（空白／錨圓鈕／刪除）、下面長膠囊換行；復原／原文／貼上／取消收在顯示窗右上。
翻譯可選「譯文＋原文」（譯文換行，（中文原文）；跟 Mac 版同格式）。

鍵盤 ↔ app 溝通：App Group `group.ltd.intention.talky` 的 `Library/state.json`（app 寫、鍵盤讀）＋ Darwin 通知（start／stop／cancel／ping／consumed）。每一步記在 `Library/talky-events.log`（只記步驟與字數、不記內容）。

## 整理（Typeless 那一半）

| 設定 | 走哪 | 失敗時 |
|---|---|---|
| Claude 訂閱 | 手機經 Tailscale 送到 Mac mini 內網 `/api/talky/polish`，mini 用本機登入的 Claude Code（＝你的訂閱）整理；預設 Opus 5.5，實測每句 1.9–2.9 秒 | 連不到 mini（Tailscale 沒開）→ Apple → 原話 |
| Apple（預設） | iOS 27：Apple 私有雲模型 → 手機本機模型；改口句先用規則換好（Corrections） | 只加標點的原話 |
| 不整理 | 只做繁體化＋全形標點＋中英空格 | — |

mini 那條路只收你本人 Tailscale 帳號底下的裝置（認 Tailscale 自己附上的身分標頭；公開的 Funnel 流量與偽造標頭實測都 403），手機這邊不存任何金鑰。

本機小模型實測會出錯（把「幫我寫一封信」真的寫成信、把問句回答掉、把改口反轉、抄示範裡的英文字），
所以 `Guards` 會機械檢查每一句輸出，抓到就退回原話：**寧可沒整理，不可改錯意思。**
在 Mac 上用同一顆模型跑 16 句測試：全數正確或安全退回，平均 0.9 秒。

## 檔案

| 路徑 | 是什麼 |
|---|---|
| `Talky.xcodeproj` | Xcode 專案（資料夾同步：新檔丟進資料夾就會編進去） |
| `App/DictationEngine.swift` | 狀態機：待命 → 聽 → 整理 → 交給鍵盤 |
| `App/AudioTap.swift` | 待命期間一直開著的麥克風（留 0.4 秒前奏，第一個字不會被切掉） |
| `App/LiveTranscriber.swift` | 即時辨識（SpeechTranscriber；不支援的機型退 DictationTranscriber） |
| `App/Polisher.swift` | 整理：prompt、Guards、Apple／Claude 訂閱路由 |
| `App/Corrections.swift` | 改口（「十點啊不對兩點」）：規則找新舊說法、程式替換 |
| `App/TalkyShortcuts.swift` | 捷徑／Siri 的「Talky 待命」 |
| `LiveActivity/StandbyIntents.swift` | 原地開／關待命的意圖（控制中心、動作按鈕）＋動態島資料 |
| `Widgets/TalkyWidgets.swift` | 控制中心按鈕＋動態島／鎖定畫面的長相 |
| `App/TextRules.swift` | 簡轉繁、標點全形、幻聽過濾（Mac 版 TextUtil 移植） |
| `App/HomeView.swift`、`App/BounceView.swift` | 首頁、被鍵盤叫醒那頁 |
| `Keyboard/` | 鍵盤擴充（`KeyboardViewController`／`KeyboardModel`／`KeyboardView`） |
| `Shared/Bridge.swift` | 鍵盤 ↔ app 傳話層 |
| `Shared/Theme.swift` | Talky 設計規則（Mac 版 `Neu.swift` 移植：軟浮雕材料、米字光點、錨圓鈕、凹槽、分段選擇）＋原生鍵盤灰 |
| `App/MacRelay.swift` | 用你自己 Mac 的訂閱：配對（QR 碼）、加密請求、同時試 Mac 的每個位址 |
| `Shared/Translate.swift` | 翻譯：語言、對象（給 Claude 的語氣說明）、翻譯目標、口吻、「這一句翻成什麼」 |
| `App/KeyboardProbe.swift` | 開發用：模擬器裡直接叫出 Talky 鍵盤截圖（只在 Debug 版） |
| `scripts/sim-keyboard.sh` | 開發用：模擬器看鍵盤各狀態（寫 state.json＋notifyutil 叫鍵盤重讀＋截圖） |
| `scripts/make-ios-icon.swift` | 畫 app 圖示（跟 Mac 版同一個六臂米字） |
| `install.sh` | 編譯＋簽名＋裝到手機 |

## 開發

- 模擬器建置：`xcodebuild -project Talky.xcodeproj -scheme Talky -sdk iphonesimulator -derivedDataPath .build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build`
- 模擬器**跑不了 SpeechTranscriber**（`isAvailable`＝false）；辨識要在真機或 Mac 上測。
- 看真機畫面：`xcrun devicectl device capture screenshot --device <手機> --destination x.png`；看事件記錄：`xcrun devicectl device copy from --device <手機> --domain-type appGroupDataContainer --domain-identifier group.ltd.intention.talky --source Library/talky-events.log --destination x.log`。
- DEBUG 版可以拿音檔走完整條辨識＋整理：`xcrun simctl launch <裝置> ltd.intention.talky.ios -TalkyFeedFile <音檔>`，結果看 App Group 的 `state.json`。
- 真機翻譯測試：`bash ios/scripts/device-test.sh translate`（Debug 版；三句各翻成一個目標，印譯文／意思／整理好的中文）。
- 模擬器看鍵盤：先把 Talky 加進模擬器的鍵盤清單（`xcrun simctl spawn <裝置> defaults write -g AppleKeyboards -array "zh_Hant-Zhuyin@sw=Zhuyin;hw=Automatic" "ltd.intention.talky.ios.keyboard" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji"` 後重開模擬器），再 `SIM=<裝置> bash ios/scripts/sim-keyboard.sh listening-tr dark x.png`。模擬器開不了「完整取用」，Debug 版在模擬器裡讀得到 App Group 就當作有開。
- bundle id：app `ltd.intention.talky.ios`、鍵盤 `.keyboard`、小工具 `.widgets`（跟 Mac 版 `ltd.intention.talky` 分開，互不影響）。
