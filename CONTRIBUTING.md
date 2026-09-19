# 參與 Talky / Contributing to Talky

（English below）

## 先知道的事

- **範圍**：macOS 14 以上、Apple 晶片。Intel 與其他平台的 PR 不會收，理由在 README「安裝」一節。
- **語言**：程式註解、commit 訊息、issue 都可以用繁體中文或英文。註解裡常見「病史」＝當初為什麼這樣寫的踩坑記錄，改那段 code 之前先讀完。
- **設計原則**：給完全不會用電腦的人也能自己裝好。任何新功能都要問「阿嬤看得懂嗎」；看不懂就收進「延伸選項」，主畫面不加東西。
- **不會靜默假裝成功**：整理走了哪一條路（雲端／本機／原稿）一定要在面板上看得到。改整理路由時保住這條。

## 怎麼建

```bash
xcode-select --install
bash scripts/vendor-fetch.sh     # 引擎二進位進 vendor/（不進 git）
bash build.sh                    # 產出 build/Talky.app
```

沒有 Xcode 專案檔：`build.sh` 就是一發 `swiftc app/Sources/*.swift`。改完直接重跑 `build.sh`，十幾秒。
同一時間想留一顆能用的 app：`TALKY_BUILD_DIR=build-dev bash build.sh` 另開目錄建。

程式怎麼分：

| 檔 | 管什麼 |
|---|---|
| `app/Sources/main.swift` | 進入點、命令列旗標（`--doctor`、`--ime-polish`、`--demo-text` 等） |
| `Dictation.swift` | 熱鍵、錄音、面板、貼字、整理路由與退路 |
| `Brains.swift`／`BrainsView.swift` | 整理方式的選擇邏輯與設定畫面 |
| `ClaudeCLI.swift`／`CodexCLI.swift`／`LocalLLM.swift`／`Endpoints.swift` | 各條整理路徑 |
| `Translate.swift` | 翻譯模式：語言、對象、敬語規則 |
| `Onboarding.swift`／`WizardGlyphs.swift` | 五步精靈 |
| `Neu.swift` | 介面元件與外觀 |
| `SharedPaths.swift` | 借用姊妹 app 已下載的模型（唯一的跨 app 耦合點） |
| `Diagnostics.swift` | `--doctor` 與「匯出診斷檔」 |

## 送 PR 之前

1. `bash build.sh` 能過，`build/Talky.app/Contents/MacOS/Talky --doctor` 印得出來。
2. 動到介面或整理路由：照 [TESTING.md](TESTING.md) 跑相關的那幾條，PR 裡寫你跑了哪幾條、看到什麼。
3. `bash scripts/check-clean.sh` 綠燈（不准出現金鑰、私人路徑、內部人名）。
4. 一個 PR 做一件事。commit 訊息第一行講「改了什麼、為什麼」，可以長；病史寫進 code 註解，不要只寫在 PR。
5. 不刪使用者資料、不動使用者的其他設定、不幫使用者填 API 金鑰（`AGENTS.md` §7 的規矩對程式碼一樣適用）。

## 回報問題

用 issue 模板。最有用的三樣：一句話「做了什麼、看到什麼」、設定 → 一般 → 「匯出診斷檔到桌面」那份 txt（不含金鑰）、有畫面問題就截圖。

## 商標

`app/Resources/Brand/` 裡的圖檔是商標，不在 MIT 範圍內。fork 可以照原樣保留讓 app 顯示身份，但不要拿去當你自己產品的標誌。細則見 [app/Resources/Brand/TRADEMARK.md](app/Resources/Brand/TRADEMARK.md)。

---

## Before you start

- **Scope**: macOS 14+, Apple silicon only. PRs for Intel or other platforms will not be merged; the reasoning is in the README under Install.
- **Language**: code comments, commit messages and issues may be in Traditional Chinese or English. Comments often contain a "病史" (case history): why the code is the way it is. Read it before changing that block.
- **Design rule**: someone who has never used a computer must be able to set this up alone. Every new feature gets asked "would grandma understand this?". If not, it goes under "More options"; the main screens do not grow.
- **Never silently pretend to succeed**: which path tidying took (cloud / local / raw) must always be visible on the panel. Keep that when touching the routing.

## Building

```bash
xcode-select --install
bash scripts/vendor-fetch.sh     # engine binaries into vendor/ (not in git)
bash build.sh                    # produces build/Talky.app
```

There is no Xcode project; `build.sh` is a single `swiftc app/Sources/*.swift`. Rebuild after each change, it takes seconds.
To keep a working copy running while you hack: `TALKY_BUILD_DIR=build-dev bash build.sh`.

Layout: see the table above. `main.swift` is the entry point and CLI flags, `Dictation.swift` owns hotkey / recording / panel / paste / routing, `Brains*.swift` the tidying option logic and UI, `Translate.swift` translate mode, `Onboarding.swift` the wizard, `Neu.swift` the UI kit, `SharedPaths.swift` the one cross-app coupling point, `Diagnostics.swift` the doctor and diagnostics export.

## Before opening a PR

1. `bash build.sh` passes and `build/Talky.app/Contents/MacOS/Talky --doctor` prints.
2. If you touched UI or routing, run the relevant items in [TESTING.md](TESTING.md) and say in the PR which ones and what you saw.
3. `bash scripts/check-clean.sh` is green (no keys, private paths or internal names).
4. One PR, one change. First line of the commit says what and why; it can be long. Case histories go into code comments, not only into the PR.
5. Never delete user data, never touch the user's other settings, never fill in API keys for the user (the rules in `AGENTS.md` §7 apply to code too).

## Reporting issues

Use the issue templates. The three most useful things: one sentence "what I did, what I saw", the diagnostics txt from Settings → General → Export diagnostics to Desktop (contains no keys), and a screenshot for anything visual.

## Trademarks

The image files under `app/Resources/Brand/` are trademarks, not covered by MIT. Forks may keep them as-is so the app can show its identity; do not use them to brand your own product. Details in [app/Resources/Brand/TRADEMARK.md](app/Resources/Brand/TRADEMARK.md).
