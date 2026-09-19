// SettingsWindow — 設定頁（一般／進階）
//
// 設定視窗重置：
//   一般：外觀／快捷鍵（目前＋「重設快捷鍵」錄製面）／常用詞／檢查（重新跑精靈、匯出診斷檔）
//   進階：讓你的 AI 帶你接好（最上面）／用什麼來整理（三顆可見＋更多選項，整列可點、每顆有測試）／其他
//   頁尾只留 Powered by（沒做的事寫在 README「還沒做的」節）。
//   0.1.2 減法（太複雜的收起來）：貼字方式、這台電腦、打開記錄檔、重啟引擎、常用詞檔案路徑 五樣拿掉——
//   記憶體／port／資料夾／記錄檔都在「匯出診斷檔」裡；重啟引擎在出錯時的面板與試講頁才出現；貼字方式留 defaults（pasteMode）。

import AppKit
import SwiftUI

struct SettingsView: View {
    var initialTab = 0
    var onWizard: () -> Void = {}

    @ObservedObject var state = AppState.shared
    @State private var tab = 0
    @State private var glossary = TextUtil.localGlossary() ?? ""
    @State private var glossaryNote = ""
    @State private var statusLight = Dictation.showStatusLight
    @State private var launchAtLogin = AppState.shared.launchAtLoginOn
    @State private var showHotkeySheet = false
    @State private var triggerLabel = Dictation.trigger.longLabel
    @State private var appearanceIndex = Dictation.Appearance.allCases.firstIndex(of: Dictation.appearance) ?? 0
    @State private var diagNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.lg) {
            HStack {
                Text("設定").font(NeuFont.ui(NeuType.title, true)).foregroundColor(Neu.inkStrong)
                Spacer()
                NeuSegmented(items: ["一般", "進階"], selection: $tab).frame(width: 180)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: NeuSpace.hero) {
                    if tab == 0 { general } else { advanced }
                }
                .padding(.vertical, NeuSpace.sm)
            }
            PoweredBy()
        }
        .padding(NeuSpace.xl)
        .frame(width: 480, height: 600, alignment: .top)
        .background(Neu.stage)
        .onAppear {
            tab = initialTab
            launchAtLogin = state.launchAtLoginOn
        }
        .sheet(isPresented: $showHotkeySheet) {
            HotkeyRecorderView {
                triggerLabel = Dictation.trigger.longLabel
                showHotkeySheet = false
            }
        }
    }

    // ── 一般 ──

    private var general: some View {
        VStack(alignment: .leading, spacing: NeuSpace.hero) {
            section("外觀") {
                NeuSegmented(
                    items: Dictation.Appearance.allCases.map(\.label),
                    selection: Binding(
                        get: { appearanceIndex },
                        set: { i in
                            appearanceIndex = i
                            Dictation.appearance = Dictation.Appearance.allCases[i]
                        }))
            }
            section("快捷鍵") {
                HStack(spacing: NeuSpace.md) {
                    Text("目前：\(triggerLabel)").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkStrong)
                    Spacer()
                    NeuChip(title: "重設快捷鍵") { showHotkeySheet = true }
                }
            }
            section("翻譯（左 ⌘ 連按兩下）") {
                TranslateSettingsView()
            }
            section("常用詞") {
                NeuNote(text: "人名、公司名打在這裡，會認得。用頓號分隔。")
                // 內距 12、高 130：游標（插入點）在第一行與最後一行都不會貼到框邊被裁（病史：游標貼邊被裁）
                TextEditor(text: $glossary)
                    .font(NeuFont.ui(NeuType.caption))
                    .frame(height: 130)
                    .scrollContentBackground(.hidden)
                    .padding(NeuSpace.md)
                    .neuDebossed(NeuRadius.card, depth: 0.9)
                HStack(spacing: NeuSpace.md) {
                    NeuChip(title: "儲存") {
                        glossaryNote = TextUtil.writeGlossary(glossary) ? "已存" : "存檔失敗"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { glossaryNote = "" }
                    }
                    if !glossaryNote.isEmpty {
                        Text(glossaryNote).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                    }
                    Spacer()
                }
            }
            section("檢查") {
                HStack(spacing: NeuSpace.md) {
                    NeuChip(title: "重新跑設定精靈") { onWizard() }
                    NeuChip(title: "匯出診斷檔到桌面") {
                        if let u = Diagnostics.export() {
                            diagNote = "已存到桌面：\(u.lastPathComponent)，出問題把這份傳回來"
                            NSWorkspace.shared.activateFileViewerSelecting([u])
                        } else {
                            diagNote = "寫檔失敗（記錄檔有原因）"
                        }
                    }
                    if !diagNote.isEmpty {
                        Text(diagNote).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
        }
    }

    // ── 進階 ──

    private var advanced: some View {
        VStack(alignment: .leading, spacing: NeuSpace.hero) {
            // 「複製貼給你的 AI、讓它一步一步帶著做完」放進階最上面
            section("讓你的 AI 帶你接好") {
                PasteToAIChip()
            }
            section("用什麼來整理") {
                NeuNote(text: "點一整列就選到。每顆都能按「測試」。")
                BrainsList(compact: true)
            }
            section("其他") {
                Toggle(isOn: $statusLight) {
                    Text("在選單列顯示狀態燈").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkStrong)
                }
                .toggleStyle(.switch)
                .onChange(of: statusLight) { _, v in
                    Dictation.showStatusLight = v
                    NotificationCenter.default.post(name: .talkyStatusLightChanged, object: nil)
                }
                Toggle(isOn: $launchAtLogin) {
                    Text("開機時自動啟動 Talky").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkStrong)
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, v in state.setLaunchAtLogin(v) }
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) {
            Text(title).font(NeuFont.ui(NeuType.body, true)).foregroundColor(Neu.inkStrong)
            content()
        }
    }
}

extension Notification.Name {
    static let talkyStatusLightChanged = Notification.Name("talkyStatusLightChanged")
}

// ── 重設快捷鍵（錄製面）──

struct HotkeyRecorderView: View {
    var onDone: () -> Void

    @State private var index = HotkeyTrigger.allCases.firstIndex(of: Dictation.trigger) ?? 0
    @State private var detected = false
    @State private var waiting = false
    @State private var note = ""
    private let original = Dictation.trigger

    private var current: HotkeyTrigger { HotkeyTrigger.allCases[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.xl) {
            HStack {
                TalkyMark(mode: waiting ? .listening : .idle, size: 12).frame(width: 28, height: 28)
                Text("重設快捷鍵").font(NeuFont.ui(NeuType.title, true)).foregroundColor(Neu.inkStrong)
                Spacer()
            }
            NeuNote(text: "選一顆修飾鍵，連按兩下就開始講、再按一次結束。按「按看看」可以當場確認。")
            VStack(spacing: NeuSpace.sm) {
                Text("雙擊 " + current.shortLabel)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundColor(Neu.inkStrong)
                Text(waiting ? "正在等你按…" : (detected ? "偵測到了" : current.longLabel))
                    .font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NeuSpace.xl)
            .neuDebossed(NeuRadius.card, depth: 0.95)
            NeuSegmented(
                items: HotkeyTrigger.allCases.map { "雙擊 " + $0.shortLabel },
                selection: Binding(
                    get: { index },
                    set: { i in
                        index = i
                        detected = false
                        note = ""
                        Dictation.trigger = HotkeyTrigger.allCases[i]
                        DictationController.shared.syncWithSettings()
                    }))
            HStack(spacing: NeuSpace.md) {
                NeuChip(title: waiting ? "等你按…" : "按看看", enabled: !waiting) { arm() }
                if !note.isEmpty { NeuNote(text: note) }
                Spacer()
            }
            NeuNote(text: "雙擊修飾鍵不會跟別的 app 打架；任意組合鍵（例如 ⌃⌥Space）的錄製排在下一版。")
            Spacer()
            HStack {
                NeuChip(title: "取消") {
                    Dictation.trigger = original
                    DictationController.shared.syncWithSettings()
                    DictationController.shared.hotkeyTestHandler = nil
                    onDone()
                }
                Spacer()
                NeuCapsuleButton(title: "儲存", height: 40) {
                    DictationController.shared.hotkeyTestHandler = nil
                    onDone()
                }
                .frame(width: 140)
            }
            PoweredBy()
        }
        .padding(NeuSpace.xl)
        .frame(width: 420, height: 520)
        .background(Neu.stage)
    }

    private func arm() {
        detected = false
        note = ""
        waiting = true
        DictationController.shared.hotkeyTestHandler = {
            detected = true
            waiting = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if waiting {
                waiting = false
                DictationController.shared.hotkeyTestHandler = nil
                note = Dictation.axTrusted ? "沒偵測到，確認你連按的是這顆鍵。" : "沒偵測到：要先開輔助使用。"
            }
        }
    }
}

// ── 翻譯模式設定（一個「對象」驅動全部語言，泰文另問性別）──

struct TranslateSettingsView: View {
    @State private var hotkeyOn = Translate.enabledHotkey
    @State private var target = Translate.target
    @State private var audienceIndex = TranslateAudience.allCases.firstIndex(of: Translate.audience) ?? 1
    @State private var genderIndex = SpeakerGender.allCases.firstIndex(of: Translate.gender) ?? 0
    @State private var outputIndex = Translate.withOriginal ? 1 : 0
    @State private var extra = Translate.extraLangs

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) {
            Toggle(isOn: $hotkeyOn) {
                Text("左 ⌘ 連按兩下＝講中文、貼外語").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkStrong)
            }
            .toggleStyle(.switch)
            .onChange(of: hotkeyOn) { _, v in Translate.enabledHotkey = v }
            NeuNote(text: "右 ⌘ 照舊是整理。聽的時候面板上有一排語言籤，點一下就換；這裡選的是預設語言。")

            Text("預設語言").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: NeuSpace.sm)], alignment: .leading, spacing: NeuSpace.sm) {
                ForEach(TranslateTarget.enabled) { t in
                    TargetChip(target: t, selected: t == target) {
                        target = t
                        Translate.target = t
                    }
                }
            }
            Toggle(isOn: $extra) {
                Text("多四種：德文、葡萄牙文、簡體中文、粵語").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkStrong)
            }
            .toggleStyle(.switch)
            .onChange(of: extra) { _, v in
                Translate.extraLangs = v
                if !TranslateTarget.enabled.contains(target) {
                    target = .en
                    Translate.target = .en
                }
            }

            Text("對象（決定每種語言的敬語與稱謂）").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
            NeuSegmented(
                items: TranslateAudience.allCases.map(\.label),
                selection: Binding(
                    get: { audienceIndex },
                    set: { i in
                        audienceIndex = i
                        Translate.audience = TranslateAudience.allCases[i]
                    }))

            Text("我的性別（只影響泰文的句尾 ครับ／ค่ะ）").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
            NeuSegmented(
                items: SpeakerGender.allCases.map(\.label),
                selection: Binding(
                    get: { genderIndex },
                    set: { i in
                        genderIndex = i
                        Translate.gender = SpeakerGender.allCases[i]
                    }))

            Text("貼什麼").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
            NeuSegmented(
                items: ["只貼譯文", "譯文＋（原文）"],
                selection: Binding(
                    get: { outputIndex },
                    set: { i in
                        outputIndex = i
                        Translate.withOriginal = (i == 1)
                    }))
            NeuNote(text: "翻譯用的大腦跟整理同一顆（設定 → 進階）。內建小模型翻泰文、越南文、印尼文品質有限，建議用 Claude 或 ChatGPT。")
        }
    }
}
