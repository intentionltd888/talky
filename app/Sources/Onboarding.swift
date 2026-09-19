// Onboarding — 首啟精靈（五步，一個視窗，中途退出下次從斷點續）
//
// 0.1.2：8 頁砍成 5 頁（阿嬤自己也裝得起來）——
//   0 歡迎（按「開始設定」就在背景下載聽寫模型，不再有「下載」頁）→ 1 麥克風 → 2 輔助使用 →
//   3 整理方式（app 已替你選好：有 ChatGPT／Claude 登入就用它，沒有就內建模型或不整理；要換才展開）→
//   4 試講一句（就是連按兩下右 ⌘；原本的「快捷鍵」頁併進來，換鍵移到設定）→
//   5 好了（就緒清單；開機自啟與狀態燈直接預設開，設定裡能關；缺東西才露出「貼給你的 AI」那扇門）
// 規則不變：每步答得出「發生什麼／進度到哪／還要多久／能不能走開」；可跳過的標明；不裝死。
// 每一步固定三塊：大標＋一句為什麼 → 「你要做的」1-2-3（做一個動作、看到什麼）→ 狀態列＋下一步（按不了就寫原因）。
// 0.1.3：小字全砍、操作說明改圖示（WizardGlyphs）、第 3 步改兩張大卡並排（用我的訂閱／用本機模型）＋「延伸選項」、
//   第 4 步講成功就顯示「你成功了，歡迎使用」並自動進最後一頁。

import AVFoundation
import AppKit
import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    var onOpenSettings: () -> Void = {}

    @ObservedObject private var app = AppState.shared
    @ObservedObject private var codexInstall = CodexInstall.shared
    @ObservedObject private var codexLogin = CodexLogin.shared
    @ObservedObject private var claudeInstall = ClaudeInstall.shared
    @ObservedObject private var claudeLogin = ClaudeLogin.shared
    @State private var claudeCode = ""
    @State private var step: Int

    static let total = 5  // 顯示用：1/5…5/5（歡迎頁不算）
    /// 截圖／設計審查用：`defaults write ltd.intention.talky wizardDemoUngranted -bool YES` → 第 1／2 步照「還沒給權限」畫
    private var demoUngranted: Bool { UserDefaults.standard.bool(forKey: "wizardDemoUngranted") }

    /// startAt：`--open wizard:N` 直接跳到第 N 步（設計審查與截圖用）；nil＝從上次斷點續
    init(onFinish: @escaping () -> Void, onOpenSettings: @escaping () -> Void = {}, startAt: Int? = nil) {
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
        _step = State(initialValue: min(Self.total, max(0, startAt ?? Dictation.onboardingStep)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.lg) {
            header
            Group {
                switch step {
                case 0: welcome
                case 1: micStep
                case 2: axStep
                case 3: brainStep
                case 4: tryStep
                default: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(NeuSpace.xl)
        .frame(width: 460, height: 640, alignment: .top)
        .background(Neu.stage)
        .onChange(of: step) { _, s in Dictation.onboardingStep = s }
    }

    // ── 版頭／頁尾 ──

    private var header: some View {
        HStack {
            if step == 0 {
                Text("©(TW)(zh)").font(NeuFont.ui(NeuType.micro, true)).foregroundColor(Neu.inkMid)
                Spacer()
                Text("Talky Voice Typing").font(NeuFont.ui(NeuType.micro, true)).foregroundColor(Neu.inkMid)
            } else {
                Text("\(step) / \(Self.total)")
                    .font(NeuFont.mark(NeuType.micro, false)).foregroundColor(Neu.inkSoft)
                Spacer()
                TalkyLogotype(height: 16)
            }
        }
    }

    /// 頁尾：下載在背景跑的時候，每一頁底下都看得到進度（沒有獨立的下載頁了）
    private var footer: some View {
        VStack(spacing: NeuSpace.md) {
            if step >= 1, let f = app.downloadFraction {
                HStack(spacing: NeuSpace.sm) {
                    NeuGroove(fill: CGFloat(f), height: 8)
                    Text(String(format: "%@ %.0f%%", app.downloadLabel, f * 100)).font(NeuFont.ui(NeuType.micro))
                        .foregroundColor(Neu.inkMid)
                }
            }
            PoweredBy(showLogotype: false)
        }
    }

    private func nav(
        next: String = "下一步", canSkip: Bool = false, skipTitle: String = "先跳過", nextEnabled: Bool = true,
        reason: String? = nil, nextAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            if !nextEnabled, let r = reason { NeuNote(text: r) }
            HStack(spacing: NeuSpace.md) {
                if step > 0 {
                    NeuIconButton(systemName: "chevron.left", size: 30) { withAnimation(NeuMotion.ui) { step -= 1 } }
                }
                if canSkip {
                    NeuChip(title: skipTitle) { withAnimation(NeuMotion.ui) { step += 1 } }
                }
                NeuCapsuleButton(title: next, enabled: nextEnabled) {
                    if let a = nextAction { a() } else { withAnimation(NeuMotion.ui) { step += 1 } }
                }
            }
        }
    }

    /// 「你要做的」1-2-3：每一步都給完全不會用的人一份動作清單（做什麼、會看到什麼）
    private func todo(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            Text("你要做的").font(NeuFont.ui(NeuType.micro, true)).foregroundColor(Neu.inkSoft)
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top, spacing: NeuSpace.sm) {
                    Text("\(i + 1)").font(NeuFont.mark(NeuType.caption)).foregroundColor(Neu.inkMid)
                        .frame(width: 14, alignment: .trailing)
                    Text(t).font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func heading(_ t: String, mark: TalkyMark.Mode? = .idle) -> some View {
        HStack(spacing: NeuSpace.md) {
            if let m = mark { TalkyMark(mode: m, size: 15).frame(width: 34, height: 34) }
            Text(t).font(NeuFont.ui(NeuType.hero, true)).foregroundColor(Neu.inkStrong)
        }
    }

    // ── 0 歡迎 ──

    /// 歡迎頁＝B2 海報版：標語先講、大字標壓在下面、specimen 小字圍四周、底部三行英文置中。
    /// 呼應 specimen 版面但全用墨色不用藍；文字五格照 specimen 定案（version 那格是 Powered by INTENTION . (c) * 2026）。
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: NeuSpace.lg)
            Text("Don't type").font(NeuFont.ui(36, true)).foregroundColor(Neu.inkStrong)
            Text("Just talky.").font(NeuFont.ui(36, true)).foregroundColor(Neu.inkStrong)
            Spacer().frame(height: NeuSpace.lg)
            TalkyLogotypeWide(color: Neu.inkStrong)
            Spacer().frame(height: NeuSpace.sm)
            HStack(spacing: 4) {
                Text("Powered by").font(NeuFont.ui(NeuType.micro, true)).foregroundColor(Neu.inkMid)
                IntentionWordmark(height: 8, color: Neu.inkMid)
                Text(". (c) * 2026").font(NeuFont.ui(NeuType.micro, true)).foregroundColor(Neu.inkMid)
            }
            HStack {
                Spacer()
                Text("③Brains / zh-TW").font(NeuFont.ui(NeuType.micro, true)).foregroundColor(Neu.inkMid)
            }
            .padding(.top, 6)
            Spacer()
            VStack(spacing: 4) {
                Text("(⌘)(⌘) right side, twice")
                Text("Talky Voice Typing : Speak, release, pasted.")
                Text("①Tap　②Talk　③Paste / zh-TW")
            }
            .font(NeuFont.ui(NeuType.caption, true)).foregroundColor(Neu.inkMid)
            .frame(maxWidth: .infinity)
            Spacer().frame(height: NeuSpace.xl)
            nav(next: "開始設定") {
                kickoff()
                withAnimation(NeuMotion.ui) { step += 1 }
            }
        }
    }

    /// 按「開始設定」那一下就把兩件不用人決定的事做掉：①背景下載聽寫模型 ②替他選整理方式。
    /// 阿嬤不需要按「開始下載」，也不需要懂什麼是大腦。
    private func kickoff() {
        if !app.whisperModelReady, app.downloadFraction == nil {
            if let msg = ModelDownload.diskShortfallMessage(need: ModelCatalog.whisper.bytes) {
                app.downloadNote = msg
            } else {
                app.downloadWhisperModel()
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { Brains.autoPick() }
    }

    // ── 1 麥克風 ──

    private var micStep: some View {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let deniedBefore = status == .denied || status == .restricted
        return VStack(alignment: .leading, spacing: NeuSpace.xl) {
            heading("讓 Talky 聽得到你")
            if !app.micGranted || demoUngranted {
                StepFlow {
                    SymbolStep(symbol: "mic.fill", label: deniedBefore ? "去系統設定" : "跳出小視窗")
                    FlowArrow()
                    SymbolStep(symbol: deniedBefore ? "switch.2" : "hand.tap.fill", label: deniedBefore ? "打開 Talky" : "按「允許」")
                    FlowArrow()
                    SymbolStep(symbol: "checkmark", label: "打勾")
                }
            }
            permissionRow(
                title: "麥克風", ok: app.micGranted && !demoUngranted,
                okText: "已允許",
                actionTitle: status == .notDetermined ? "允許" : "去系統設定"
            ) {
                if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { app.refresh() }
                    }
                } else {
                    Dictation.openMicSettings()
                }
            }
            if !app.downloadNote.isEmpty, !app.whisperModelReady, app.downloadFraction == nil {
                NeuNote(text: "聽寫模型：\(app.downloadNote)")
            }
            Spacer()
            nav(nextEnabled: app.micGranted, reason: "打勾之後才能下一步。")
        }
    }

    // ── 2 輔助使用 ──

    private var axStep: some View {
        VStack(alignment: .leading, spacing: NeuSpace.xl) {
            heading("開一個開關")
            Text("沒開，連按右 ⌘ 不會有反應。").font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong)
            if !app.axTrusted || demoUngranted {
                StepFlow {
                    SymbolStep(symbol: "gearshape.fill", label: "按「去開啟」")
                    FlowArrow()
                    SymbolStep(symbol: "switch.2", label: "打開 Talky")
                    FlowArrow()
                    SymbolStep(symbol: "lock.fill", label: "輸入密碼")
                }
            }
            permissionRow(title: "輔助使用", ok: app.axTrusted && !demoUngranted, okText: "已開啟", actionTitle: "去開啟") {
                Dictation.requestAXTrust()
                Dictation.openAXSettings()
            }
            if !app.axTrusted {
                HStack(spacing: NeuSpace.sm) {
                    Text("系統裡開了，這裡沒勾？").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                    NeuChip(title: "清掉舊記錄再開一次") {
                        Dictation.resetPermissionRecords()
                        Dictation.requestAXTrust()
                        Dictation.openAXSettings()
                    }
                    Spacer()
                }
            }
            if app.axTrusted, !app.hotkeyActive {
                HStack(spacing: NeuSpace.sm) {
                    Text("還要開「輸入監控」：").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                    NeuChip(title: "去開啟") { Dictation.openInputMonitoringSettings() }
                    Spacer()
                }
            }
            Spacer()
            nav(
                canSkip: !app.axTrusted, skipTitle: "先跳過（快捷鍵會不能用）", nextEnabled: app.axTrusted,
                reason: "打勾之後才能下一步。")
        }
    }

    private func permissionRow(title: String, ok: Bool, okText: String, actionTitle: String, action: @escaping () -> Void)
        -> some View
    {
        HStack(spacing: NeuSpace.md) {
            TalkyMark(mode: ok ? .idle : .listening, size: 11).frame(width: 26, height: 26)
            Text(title).font(NeuFont.ui(NeuType.body, true)).foregroundColor(Neu.inkStrong)
            Spacer()
            if ok {
                HStack(spacing: 6) {
                    Text(okText).font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)).foregroundColor(Neu.inkStrong)
                }
            } else {
                NeuChip(title: actionTitle, action: action)
            }
        }
        .padding(.horizontal, NeuSpace.lg).padding(.vertical, NeuSpace.md)
        .neuDebossed(NeuRadius.card, depth: 0.9)
    }

    // ── 3 整理方式：兩張大卡 ──

    @State private var picked: BrainKind = BrainKind.from(PolishMode.current)
    @State private var subKind: BrainKind?
    @State private var subStatus: (text: String, level: NeuStatusTag.Level) = ("檢查中…", .pending)
    @State private var showMore = false
    @State private var brainNote = ""
    private let brainTick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var subscriptionSelected: Bool { picked == .codex || picked == .claude }
    private var localSelected: Bool { picked == .local || picked == .off }

    /// 「用本機模型」那張卡的狀態
    private var localStatus: (text: String, level: NeuStatusTag.Level) {
        if Dictation.lite { return ("記憶體不夠，改成不整理", .pending) }
        if LocalLLM.modelReady { return ("模型已在", .ready) }
        if let f = app.downloadFraction, app.downloadLabel == "整理模型" { return (String(format: "下載中 %.0f%%", f * 100), .pending) }
        return ("會自動下載 2.5GB", .pending)
    }

    /// 兩張大卡並排：有訂閱就用訂閱，沒有就本機。
    /// 0.1.7：①訂閱那張以 Claude 為主；②「延伸選項」展開時把兩張卡收起，
    /// 清單佔滿整格、跟卡一樣寬——以前卡還留著，清單只剩 170pt 高、又窄一截，往下滑會以為壞了。
    private var brainStep: some View {
        VStack(alignment: .leading, spacing: NeuSpace.lg) {
            heading("怎麼整理你講的話")
            if !showMore {
                Text("已經替你選好了，直接下一步也可以。").font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkMid)
                HStack(alignment: .top, spacing: NeuSpace.md) {
                    BrainChoiceCard(
                        symbol: "person.crop.circle.badge.checkmark", title: "用我的訂閱", subtitle: "Claude 或 ChatGPT",
                        status: subStatus.text, statusLevel: subStatus.level,
                        advice: "建議：整理得比較好", selected: subscriptionSelected
                    ) { chooseSubscription() }
                    BrainChoiceCard(
                        symbol: "desktopcomputer", title: "用本機模型",
                        subtitle: Dictation.lite ? "不用帳號，只做繁體與標點" : "不用帳號，全在這台電腦",
                        status: localStatus.text, statusLevel: localStatus.level,
                        advice: Dictation.lite ? "沒有訂閱才選" : "效果差一點，但不用帳號", selected: localSelected
                    ) { chooseLocal() }
                }
                if let line = flowLine {
                    flowCard(line)
                } else if !brainNote.isEmpty {
                    Text(brainNote).font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("全部選項：點一列就選它。").font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkMid)
            }
            HStack(spacing: NeuSpace.md) {
                NeuChip(title: showMore ? "收起，回到兩張卡" : "延伸選項") { withAnimation(NeuMotion.ui) { showMore.toggle() } }
                Spacer()
            }
            if showMore {
                ScrollView {
                    BrainsList(compact: true, onChange: { _ in refreshPick() })
                        .padding(.vertical, NeuSpace.xs)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
            nav()
        }
        .onAppear(perform: refreshPick)
        .onReceive(brainTick) { _ in refreshPick() }
        // 裝好 Claude 直接接登入；登入完馬上綁定（Claude 這條補齊）
        .onChange(of: claudeInstall.succeeded) { _, ok in if ok { _ = ClaudeLogin.shared.start() } }
        .onChange(of: claudeLogin.succeeded) { _, ok in
            if ok {
                Brains.select(.claude)
                picked = .claude
                claudeCode = ""
                brainNote = ""
                refreshPick()
            }
        }
    }

    /// 接訂閱進行中的一行狀態：Claude 安裝／登入 → ChatGPT 安裝／登入
    private var flowLine: String? {
        if claudeInstall.running || claudeInstall.failed { return claudeInstall.note }
        if claudeLogin.running { return claudeLogin.note }
        if claudeLogin.succeeded, !claudeLogin.note.isEmpty { return claudeLogin.note }
        if codexInstall.running || codexInstall.failed { return codexInstall.note }
        if codexLogin.running { return codexLogin.note }
        if codexLogin.succeeded, !codexLogin.note.isEmpty { return codexLogin.note }
        return nil
    }

    /// 進行中那張凹卡：一行狀態＋（下載）進度＋（Claude 要代碼時）貼代碼格＋取消／再開瀏覽器
    private func flowCard(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            Text(line).font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong)
                .fixedSize(horizontal: false, vertical: true)
            if codexInstall.running { NeuGroove(fill: CGFloat(codexInstall.fraction), height: 10) }
            if claudeLogin.running, claudeLogin.needsCode {
                HStack(spacing: NeuSpace.sm) {
                    TextField("貼上瀏覽器給你的代碼", text: $claudeCode)
                        .textFieldStyle(.plain)
                        .font(NeuFont.ui(NeuType.caption))
                        .foregroundColor(Neu.inkStrong)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .neuDebossed(10, depth: 0.8)
                        .onSubmit { claudeLogin.submit(code: claudeCode) }
                    NeuChip(title: "送出", enabled: !claudeCode.trimmingCharacters(in: .whitespaces).isEmpty) {
                        claudeLogin.submit(code: claudeCode)
                    }
                }
            }
            HStack(spacing: NeuSpace.sm) {
                if claudeLogin.running, claudeLogin.url != nil {
                    NeuChip(title: "瀏覽器沒開？再開一次") { claudeLogin.openBrowserAgain() }
                }
                if codexLogin.running, codexLogin.url != nil {
                    NeuChip(title: "瀏覽器沒開？再開一次") { codexLogin.openBrowserAgain() }
                }
                if claudeInstall.running { NeuChip(title: "取消") { claudeInstall.cancel() } }
                if claudeInstall.failed, !claudeInstall.running { NeuChip(title: "複製指令") { TerminalRunner.copy(Brains.claudeInstallCommand) } }
                if claudeLogin.running { NeuChip(title: "取消") { claudeLogin.cancel() } }
                if codexInstall.running { NeuChip(title: "取消") { codexInstall.cancel() } }
                if codexLogin.running { NeuChip(title: "取消") { codexLogin.cancel() } }
                Spacer()
            }
        }
        .padding(NeuSpace.md)
        .neuDebossed(NeuRadius.card, depth: 0.7)
    }

    /// 按「用我的訂閱」：有登入的就用；沒有＝**Claude 優先**：
    /// 這台有 claude 命令列 → 直接在 app 裡登入；沒有但有 ChatGPT 桌面版 → 走 ChatGPT 登入；兩個都沒有 → 裝 Claude Code → 自動接登入 → 登入完自動綁定。
    /// 按下去就跳出登入頁，登入完馬上綁定。
    private func chooseSubscription() {
        if let k = subKind {
            Brains.select(k)
            picked = k
            brainNote = ""
            return
        }
        if claudeInstall.running || claudeLogin.running || codexInstall.running || codexLogin.running { return }
        if ClaudeCLI.available {
            if !ClaudeLogin.shared.start() { brainNote = "Claude 登入起不來：按「延伸選項」看細節。" }
        } else if CodexCLI.available {
            if !CodexLogin.shared.start() { brainNote = "登入起不來：按「延伸選項」看細節。" }
        } else {
            if !ClaudeInstall.shared.start() { brainNote = "安裝起不來：按「延伸選項」看細節。" }
        }
    }

    private func chooseLocal() {
        let k: BrainKind = Dictation.lite ? .off : .local
        Brains.select(k)
        picked = k
        brainNote = ""
        AppState.shared.maybeQueuePolishDownload()
    }

    private func refreshPick() {
        DispatchQueue.global(qos: .userInitiated).async {
            let k = BrainKind.from(PolishMode.current)
            var kind: BrainKind?
            var st: (String, NeuStatusTag.Level)
            // Claude 優先；使用者自己選了 ChatGPT 就照他的
            let userPicked = BrainKind.from(PolishMode.current)
            if userPicked == .codex, CodexCLI.available, CodexCLI.loggedIn() == true {
                kind = .codex
                st = ("已接上 ChatGPT", .ready)
            } else if ClaudeCLI.available, ClaudeCLI.authStatus()?.loggedIn == true {
                kind = .claude
                st = ("已接上 Claude", .ready)
            } else if CodexCLI.available, CodexCLI.loggedIn() == true {
                kind = .codex
                st = ("已接上 ChatGPT", .ready)
            } else if ClaudeCLI.available {
                st = ("按這裡登入 Claude", .pending)
            } else if CodexCLI.available {
                st = ("按這裡登入 ChatGPT", .pending)
            } else {
                st = ("按這裡接上 Claude", .missing)
            }
            DispatchQueue.main.async {
                picked = k
                subKind = kind
                subStatus = (st.0, st.1)
            }
        }
    }

    // ── 4 講一句（＝快捷鍵）：兩關 ──

    @State private var trial = ""
    @FocusState private var trialFocused: Bool
    @State private var hotkeySeen = false
    @State private var stage = 1  // 1＝講一句 2＝再講一段亂的（條列、改口）
    @State private var firstResult = ""
    @State private var succeeded = false
    @State private var siblingTick = 0
    private let tryTick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// 第一關：⌘⌘ 超快速按兩下 → 說一句 → 再超快速按兩下。
    /// 第二關：不用先想好，盡量聊、講錯就改口，Talky 會刪多餘的、排成條列。
    /// 第二關字一出現＝「你成功了，歡迎使用」，1.8 秒後自動到最後一頁。
    private var tryStep: some View {
        let dictating = DictationController.shared.isDictating
        let key = Dictation.trigger
        let cap = key == .fn ? "fn" : (key == .rightOption ? "⌥" : "⌘")
        return VStack(alignment: .leading, spacing: NeuSpace.lg) {
            heading(succeeded ? "你成功了" : (stage == 1 ? "講一句試試" : "再來一段，隨便聊"), mark: dictating ? .listening : (succeeded ? .flash : .idle))
            if succeeded {
                Text("歡迎使用 Talky。").font(NeuFont.ui(NeuType.title, true)).foregroundColor(Neu.inkStrong)
                Text("你剛說的：" + trial.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkMid)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(NeuSpace.md).frame(maxWidth: .infinity, alignment: .leading)
                    .neuDebossed(NeuRadius.card, depth: 0.9)
                Text("之後在任何文字框都一樣：\(key.longLabel)。").font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkMid)
                Spacer()
                NeuCapsuleButton(title: "看最後一頁") { withAnimation(NeuMotion.ui) { step = 5 } }
            } else {
                if stage == 2 {
                    Text("不用先想好。想到什麼講什麼，講錯就改口，Talky 會刪掉多餘的、排成條列。")
                        .font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong).fixedSize(horizontal: false, vertical: true)
                }
                if app.whisperModelReady {
                    StepFlow {
                        GlyphStep(label: "超快速按兩下") { DoubleKey(label: cap) }
                        FlowArrow()
                        if stage == 1 {
                            SymbolStep(symbol: "waveform", label: "說「今天天氣不錯」")
                        } else {
                            SymbolStep(symbol: "list.bullet", label: "聊一段（下面有範例）")
                        }
                        FlowArrow()
                        GlyphStep(label: "再超快速按兩下") { DoubleKey(label: cap) }
                    }
                    if stage == 2 {
                        Text("例如：「明天要做三件事，第一去市場，第二打電話給小明，啊不對是小華，第三……嗯……睡午覺」")
                            .font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkMid).fixedSize(horizontal: false, vertical: true)
                    }
                } else if let f = app.downloadFraction {
                    Text(String(format: "聽寫模型下載中 %.0f%%，下載完才能講。可以先按「下一步」。", f * 100))
                        .font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: NeuSpace.sm) {
                        Text("聽寫模型還沒下載。").font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkStrong)
                        NeuChip(title: "開始下載") { app.downloadWhisperModel() }
                    }
                }
                TextField(stage == 1 ? "講完的字會出現在這裡" : "整理好的會出現在這裡", text: $trial, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(stage == 1 ? 2 : 4, reservesSpace: true)
                    .font(NeuFont.ui(NeuType.body))
                    .foregroundColor(Neu.inkStrong)
                    .focused($trialFocused)
                    .padding(NeuSpace.md)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .neuDebossed(NeuRadius.card, depth: 0.9)
                HStack(spacing: NeuSpace.md) {
                    NeuChip(title: dictating ? "結束並貼上" : "用按的", enabled: app.whisperModelReady) {
                        trialFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { DictationController.shared.toggle() }
                    }
                    if stage == 2, !firstResult.isEmpty {
                        Text("第一句成功了。").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                    } else if hotkeySeen {
                        Text(dictating ? "聽到了，講吧。" : "整理中…").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                    }
                    Spacer()
                }
                if !app.axTrusted {
                    HStack(spacing: NeuSpace.sm) {
                        Text("沒開輔助使用，鍵盤不會動：").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                        NeuChip(title: "回去開") { withAnimation(NeuMotion.ui) { step = 2 } }
                        Spacer()
                    }
                } else if !app.hotkeyActive {
                    HStack(spacing: NeuSpace.sm) {
                        Text("還要開「輸入監控」：").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                        NeuChip(title: "去開啟") { Dictation.openInputMonitoringSettings() }
                        Spacer()
                    }
                }
                if SharedPaths.siblingAppRunning, SharedPaths.siblingIMEEnabled {
                    HStack(spacing: NeuSpace.sm) {
                        Text("會議記錄 app 也在聽右 ⌘，會搶：").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                        NeuChip(title: "關掉它的輸入法") {
                            SharedPaths.disableSiblingIME()
                            siblingTick += 1
                        }
                        Spacer()
                    }
                    .id(siblingTick)
                }
                if case .broken(let e) = app.health {
                    HStack(spacing: NeuSpace.sm) {
                        NeuNote(text: e)
                        NeuChip(title: "重啟引擎") { app.restartEngines() }
                    }
                }
                if stage == 1 {
                    Text("沒有右 ⌘？之後在設定改成 fn。").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkSoft)
                }
                Spacer()
                nav(canSkip: true, skipTitle: stage == 1 ? "先跳過" : "夠了，下一步")
            }
        }
        .onAppear { trialFocused = true }
        .onReceive(tryTick) { _ in
            if DictationController.shared.isDictating { hotkeySeen = true }
        }
        .onChange(of: trial) { _, t in
            guard !succeeded, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if stage == 1 {
                // 第一關過了：留下第一句，清空框進第二關
                firstResult = t
                TalkyLog.write("wizard trial 1 ok (\(t.count) chars) → stage 2")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(NeuMotion.ui) {
                        stage = 2
                        trial = ""
                    }
                    trialFocused = true
                }
                return
            }
            succeeded = true
            TalkyLog.write("wizard trial 2 ok (\(t.count) chars) → auto advance")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if step == 4 { withAnimation(NeuMotion.ui) { step = 5 } }
            }
        }
    }

    // ── 5 好了（就緒清單）──

    @State private var brainReady: Bool?
    private let finishTick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    /// 就緒清單：五格一眼看完缺什麼、按哪裡補。病史＝跳過輔助使用就按「完成」的人會以為好了，結果雙擊右 ⌘ 沒反應。
    private var readiness: [(title: String, ok: Bool, detail: String, fix: String?, go: (() -> Void)?)] {
        var rows: [(String, Bool, String, String?, (() -> Void)?)] = []
        rows.append(("麥克風", app.micGranted, app.micGranted ? "已允許" : "沒允許：聽不到你", "去做", { withAnimation(NeuMotion.ui) { step = 1 } }))
        rows.append(("輔助使用", app.axTrusted, app.axTrusted ? "已開啟" : "沒開：連按右 ⌘ 不會有反應", "去開", { withAnimation(NeuMotion.ui) { step = 2 } }))
        let modelDetail: String
        if app.whisperModelReady {
            modelDetail = "已在"
        } else if let f = app.downloadFraction {
            modelDetail = String(format: "下載中 %.0f%%（下載完自動就緒）", f * 100)
        } else {
            modelDetail = "還沒下載：不能聽寫"
        }
        rows.append(("語音模型", app.whisperModelReady || app.downloadFraction != nil, modelDetail, "下載", { app.downloadWhisperModel() }))
        let k = BrainKind.from(PolishMode.current)
        let bDetail: String
        switch brainReady {
        case .some(true): bDetail = k.title + "，已連接"
        case .some(false): bDetail = k.title + "，還沒接上（先貼原稿）"
        case .none: bDetail = k.title + "，檢查中…"
        }
        rows.append(("整理方式", brainReady != false, bDetail, "去選", { withAnimation(NeuMotion.ui) { step = 3 } }))
        let hkDetail = app.hotkeyActive
            ? "在聽（\(Dictation.trigger.longLabel)）"
            : (app.axTrusted ? "沒接上：要「輸入監控」" : "沒開輔助使用，不會動")
        rows.append(("快捷鍵", app.hotkeyActive, hkDetail, app.axTrusted ? "去開" : nil,
            app.axTrusted ? { Dictation.openInputMonitoringSettings() } : nil))
        return rows.map { (title: $0.0, ok: $0.1, detail: $0.2, fix: $0.3, go: $0.4) }
    }

    private func checkBrain() {
        let k = BrainKind.from(PolishMode.current)
        DispatchQueue.global(qos: .userInitiated).async {
            let st = Brains.state(k)
            DispatchQueue.main.async { brainReady = (st.level == .ready) }
        }
    }

    private func readyRow(_ r: (title: String, ok: Bool, detail: String, fix: String?, go: (() -> Void)?)) -> some View {
        HStack(alignment: .center, spacing: NeuSpace.sm) {
            Image(systemName: r.ok ? "checkmark" : "minus")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(r.ok ? Neu.inkStrong : Neu.inkSoft)
                .frame(width: 14)
            Text(r.title).font(NeuFont.ui(NeuType.caption, true)).foregroundColor(Neu.inkStrong)
                .frame(width: 60, alignment: .leading)
            Text(r.detail).font(NeuFont.ui(NeuType.micro)).foregroundColor(r.ok ? Neu.inkMid : Neu.inkStrong)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !r.ok, let f = r.fix, let g = r.go { NeuChip(title: f, action: g) }
        }
        .padding(.horizontal, NeuSpace.md).padding(.vertical, 6)
    }

    private var finishStep: some View {
        let rows = readiness
        let missing = rows.filter { !$0.ok }.count
        return VStack(alignment: .leading, spacing: NeuSpace.lg) {
            heading(missing == 0 ? "好了" : "還缺 \(missing) 樣")
            Text(missing == 0 ? "之後在任何文字框\(Dictation.trigger.longLabel)就能講。" : "沒打勾的按右邊補上，或先按「完成」。")
                .font(NeuFont.ui(NeuType.body)).foregroundColor(Neu.inkMid).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in readyRow(r) }
            }
            .padding(.vertical, NeuSpace.xs)
            .neuDebossed(NeuRadius.card, depth: 0.8)
            if missing > 0 {
                // 那扇門只在缺東西時才露出：會用 AI 的人把這段貼過去，AI 照隨包的 AGENTS.md 帶著補
                PasteToAIChip()
                    .padding(NeuSpace.md)
                    .neuDebossed(NeuRadius.card, depth: 0.7)
            }
            Text("開機會自動啟動 Talky。").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkSoft)
            Spacer()
            NeuCapsuleButton(title: "完成") {
                if !Dictation.onboardingDone {
                    // 第一次跑完才設預設值（重跑精靈不覆蓋使用者後來改的）
                    app.setLaunchAtLogin(true)
                    Dictation.showStatusLight = true
                    NotificationCenter.default.post(name: .talkyStatusLightChanged, object: nil)
                }
                Dictation.onboardingDone = true
                Dictation.onboardingStep = 0
                onFinish()
            }
        }
        .onAppear(perform: checkBrain)
        .onReceive(finishTick) { _ in checkBrain() }
    }
}
