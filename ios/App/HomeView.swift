// HomeView — 主 app 首頁（Talky 設計規則＋原生鍵盤灰）
//
// 跟 Mac 版狀態視窗同一個世界：一塊材料、凸起＝可按、凹陷＝容器或已選、米字光點、Powered by 頁尾。
// 首頁只放三塊面板：狀態＋試講、翻譯目標、其他設定（一列一個凹槽，點進去各一頁）。
// 鍵盤還沒設定好時，最上面多一塊「先設定鍵盤」；三步都好了就不見。

import FoundationModels
import SwiftUI
import Translation
import UIKit

struct HomeView: View {
    @EnvironmentObject private var engine: DictationEngine
    @EnvironmentObject private var memo: Memo
    @Environment(\.scenePhase) private var scenePhase

    @State private var targets = Translate.targets
    @State private var withOriginal = Translate.withOriginal ? 1 : 0
    @State private var micOK = Permissions.micGranted
    @State private var keyboardAdded = KeyboardCheck.added
    @State private var fullAccess = KeyboardCheck.fullAccess
    @State private var copiedID: UUID?
    /// 設定頁改了東西回來，清單右邊的值要跟著變
    @State private var refresh = 0

    private var s: LiveState { engine.state }
    private var keyboardReady: Bool { micOK && fullAccess }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NeuSpace.xl) {
                    header
                    if !keyboardReady { setupPanel }
                    statusPanel
                    targetsPanel
                    settingsPanel
                    PoweredBy().padding(.horizontal, NeuSpace.xs)
                }
                .padding(.horizontal, NeuSpace.edge)
                .padding(.top, NeuSpace.sm)
                .padding(.bottom, NeuSpace.xl)
            }
            .background(Neu.material.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                refreshChecks()
                refresh += 1
            }
        }
        .tint(Neu.inkStrong)
        .onChange(of: scenePhase) { _, p in
            if p == .active { refreshChecks() }
        }
        .alert(
            engine.pairNotice ?? "", isPresented: Binding(get: { engine.pairNotice != nil }, set: { if !$0 { engine.pairNotice = nil } })
        ) {
            Button("好") {
                engine.pairNotice = nil
                refresh += 1
            }
        }
    }

    private func refreshChecks() {
        micOK = Permissions.micGranted
        keyboardAdded = KeyboardCheck.added
        fullAccess = KeyboardCheck.fullAccess
        targets = Translate.targets
    }

    // MARK: 頁首：*talky＋狀態小標

    private var header: some View {
        HStack(alignment: .center) {
            TalkyLogotype(height: 26, color: Neu.inkStrong)
            Spacer()
            NeuStatusTag(level: statusLevel, text: statusTitle)
                .padding(.horizontal, NeuSpace.md)
                .frame(height: 28)
                .neuDebossed(NeuRadius.pill, depth: 0.7)
        }
        .padding(.horizontal, NeuSpace.xs)
        .padding(.top, NeuSpace.sm)
    }

    private var statusLevel: NeuStatusTag.Level {
        engine.sessionRunning ? .ready : (s.phase == .failed ? .missing : .pending)
    }

    private var statusTitle: String {
        switch s.phase {
        case .listening: return "正在聽"
        case .working: return "整理中"
        default: return engine.sessionRunning ? "待命中" : "沒在待命"
        }
    }

    // MARK: 先設定鍵盤（三步都好了就不見）

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) {
            Text("先設定鍵盤（1 分鐘）").font(NeuFont.ui(NeuType.title, true)).foregroundStyle(Neu.inkStrong)
            step(1, done: micOK, title: "允許麥克風", detail: "聲音只在這支手機上辨識") {
                Task {
                    _ = await Permissions.request()
                    refreshChecks()
                }
            }
            step(2, done: keyboardAdded || fullAccess, title: "加入 Talky 鍵盤", detail: "設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → Talky") {
                openSettings()
            }
            step(3, done: fullAccess, title: "打開「允許完整取用」", detail: "同一頁點 Talky → 允許完整取用（鍵盤要跟 app 共用收音結果）") {
                openSettings()
            }
            NeuNote(text: "之後在任何輸入框，長按鍵盤左下角的 🌐 切到 Talky。第 3 步要叫出一次 Talky 鍵盤才會打勾。")
        }
        .padding(NeuSpace.xl)
        .neuRaised(NeuRadius.panel)
    }

    private func step(_ n: Int, done: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: NeuSpace.md) {
            ZStack {
                Circle().fill(Neu.material).frame(width: 28, height: 28).neuDebossed(14, depth: 0.7)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Neu.inkStrong)
                } else {
                    Text("\(n)").font(NeuFont.mark(13)).foregroundStyle(Neu.inkMid)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NeuFont.ui(NeuType.body, true)).foregroundStyle(done ? Neu.inkMid : Neu.inkStrong)
                Text(detail).font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.inkMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !done { NeuChip(title: "去開", height: 30, action: action) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: 狀態＋試講

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: NeuSpace.lg) {
            HStack(spacing: NeuSpace.sm) {
                TalkyMark(mode: markMode, size: 14)
                    .frame(width: 32, height: 32)
                Text(heroLine)
                    .font(NeuFont.ui(NeuType.body, true))
                    .foregroundStyle(Neu.inkStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(slotCaption).font(NeuFont.ui(NeuType.micro)).foregroundStyle(Neu.inkSoft)
                Text(slotText)
                    .font(NeuFont.ui(NeuType.body))
                    .foregroundStyle(slotIsPlaceholder ? Neu.inkSoft : Neu.inkStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if s.phase == .listening {
                    NeuGroove(fill: CGFloat(min(1, s.level * 1.4)), height: 12).padding(.top, 4)
                }
                if s.phase == .done, let r = s.result {
                    if let b = s.back, !b.isEmpty {
                        Text("意思：" + b).font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.inkMid)
                    }
                    HStack {
                        Text(pathLabel(s.path, lang: s.lang)).font(NeuFont.ui(NeuType.micro)).foregroundStyle(Neu.inkSoft)
                        Spacer()
                        Button(copied ? "已複製" : "複製") {
                            UIPasteboard.general.string = r
                            copiedID = memo.entries.first?.id
                        }
                        .font(NeuFont.ui(NeuType.caption, true))
                        .foregroundStyle(Neu.inkStrong)
                    }
                }
            }
            .padding(NeuSpace.lg)
            .neuDebossed(NeuRadius.card)

            if let p = engine.assetProgress {
                NeuNote(text: "第一次使用：下載中文語音模型 \(Int(p * 100))%")
            }
            if let m = s.message, !m.isEmpty {
                Text(m).font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.warn)
            }

            VStack(spacing: NeuSpace.xs) {
                NeuAnchorButton(
                    glyph: s.phase == .listening ? .square : .dot, size: 76, level: CGFloat(s.level),
                    dimmed: s.phase == .working
                ) {
                    if s.phase == .listening {
                        engine.stopListening()
                    } else if engine.sessionRunning {
                        engine.startListening(target: .app)
                    } else {
                        Task { await engine.beginSession(listenFor: .app) }
                    }
                }
                Text(s.phase == .listening ? "講完再點一下" : "點一下試講（不會貼到任何地方）")
                    .font(NeuFont.ui(NeuType.micro)).foregroundStyle(Neu.inkMid)
            }
            .frame(maxWidth: .infinity)

            NeuCapsuleButton(title: engine.sessionRunning ? "結束待命（關麥克風）" : "開始待命", height: 42) {
                if engine.sessionRunning {
                    engine.endSession()
                } else {
                    Task { await engine.beginSession() }
                }
            }
        }
        .padding(NeuSpace.xl)
        .neuRaised(NeuRadius.panel)
    }

    private var heroLine: String {
        if engine.sessionRunning {
            if let until = s.readyUntil, until != .distantFuture {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                return "待命到 \(f.string(from: until))：任何 App 的 Talky 鍵盤都能直接講"
            }
            return "待命中：任何 App 的 Talky 鍵盤都能直接講"
        }
        return "打開 Talky 就會待命；也能按動作按鈕或控制中心的「Talky 待命」"
    }

    private var markMode: TalkyMark.Mode {
        switch s.phase {
        case .listening: return .listening
        case .working: return .working
        case .done: return .flash
        default: return .idle
        }
    }

    private var copied: Bool { copiedID != nil && copiedID == memo.entries.first?.id }

    private var slotCaption: String {
        switch s.phase {
        case .listening: return "正在聽"
        case .working: return "整理中"
        case .done: return "剛剛那句"
        default: return memo.entries.isEmpty ? "講完的字會出現在這裡" : "上次說的話"
        }
    }

    private var slotText: String {
        switch s.phase {
        case .listening: return s.partial.isEmpty ? "…" : s.partial
        case .working: return s.partial.isEmpty ? "…" : s.partial
        case .done: return s.result ?? ""
        default: return memo.entries.first?.text ?? "按下面的圓鈕講一句試試"
        }
    }

    private var slotIsPlaceholder: Bool {
        (s.phase == .listening || s.phase == .working) && s.partial.isEmpty
            || (s.phase != .listening && s.phase != .working && s.phase != .done && memo.entries.isEmpty)
    }

    // MARK: 翻譯目標（照 Typeless：最多 4 個；鍵盤長按圓鈕往上滑時照這個順序排開）

    private var targetsPanel: some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) {
            Text("翻譯目標").font(NeuFont.ui(NeuType.title, true)).foregroundStyle(Neu.inkStrong)
            HStack(spacing: NeuSpace.md) {
                ForEach(Array(targets.enumerated()), id: \.element.id) { i, t in
                    NavigationLink {
                        TargetDetailView(index: i) { targets = Translate.targets }
                    } label: {
                        VStack(spacing: 3) {
                            Text(t.lang.label).font(NeuFont.ui(NeuType.body, true)).foregroundStyle(Neu.inkStrong)
                            Text(t.situation.label).font(NeuFont.ui(NeuType.micro)).foregroundStyle(Neu.inkMid)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                    }
                    .buttonStyle(NeuPressStyle(radius: NeuRadius.key, lift: 0.6))
                }
                if targets.count < Translate.maxTargets {
                    NavigationLink {
                        AddTargetView(existing: Set(targets.map(\.key))) { t in
                            targets.append(t)
                            Translate.targets = targets
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Neu.inkMid)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .neuDebossed(NeuRadius.key, depth: 0.8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新增翻譯目標")
                }
            }
            NeuSegmented(items: ["只打譯文", "譯文＋原文"], selection: $withOriginal, height: 38)
                .onChange(of: withOriginal) { _, v in Translate.withOriginal = v == 1 }
            NeuNote(
                text: withOriginal == 1
                    ? "打上去的樣子：譯文，下一行（中文原文）——對方看得到你原本說什麼。"
                    : "在鍵盤長按圓鈕、往上滑到其中一個放開，這一句就翻成它；點一下圓鈕＝一般中文。")
        }
        .padding(NeuSpace.xl)
        .neuRaised(NeuRadius.panel)
    }

    // MARK: 其他設定（一列一個凹槽，點進去各一頁）

    private var settingsPanel: some View {
        VStack(spacing: NeuSpace.sm) {
            row("我的口吻", Translate.speaker.label) { SpeakerView() }
            row("整理方式", polishValue) { PolishView() }
            row("待命時間", Settings.keepAliveLabel) { KeepAliveView() }
            row("常用詞", Settings.glossaryTerms.isEmpty ? "未設定" : "\(Settings.glossaryTerms.count) 個") { GlossaryView() }
            row("離線翻譯", "連不到 Mac 時用") { OfflineView() }
            row("最近 20 句", memo.entries.isEmpty ? "還沒有" : "\(memo.entries.count) 句") { MemoView() }
        }
        .padding(NeuSpace.lg)
        .neuRaised(NeuRadius.panel)
        .id(refresh)
    }

    private var polishValue: String {
        guard Settings.polishMode == .claude else { return Settings.polishMode.label }
        if let p = MacRelay.pairing {
            let brain = ["claude": "Claude", "codex": "ChatGPT"][Settings.macBrain] ?? "訂閱"
            return "\(brain)・\(p.name)"
        }
        return Settings.bridgeURL.isEmpty ? "訂閱（還沒連 Mac）" : "Claude 訂閱・自架服務"
    }

    private func row<D: View>(_ title: String, _ value: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: NeuSpace.sm) {
                Text(title).font(NeuFont.ui(NeuType.body)).foregroundStyle(Neu.inkStrong)
                Spacer()
                Text(value).font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.inkMid).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Neu.inkSoft)
            }
            .padding(.horizontal, NeuSpace.lg)
            .frame(height: 46)
            .neuDebossed(NeuRadius.pill, depth: 0.75)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func pathLabel(_ p: String?, lang: String?) -> String {
    if let l = lang.flatMap(OutputLang.init(rawValue:)) {
        return p == "apple-tr" ? "\(l.label)（Apple 離線翻譯）" : "\(l.label)（Claude 翻譯）"
    }
    switch p {
    case "pcc": return "Apple 私有雲整理"
    case "apple": return "Apple 本機整理"
    case "claude": return "Claude 整理"
    default: return "原話＋標點"
    }
}

// MARK: - 設定的各頁：同一塊材料，返回頭列＋一塊凸起面板

/// 各設定頁的外框：Mac 版 NeuBackHeader＋面板，整頁是同一塊材料（不用系統導覽列）
struct NeuPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NeuSpace.xl) {
                NeuBackHeader(title: title).padding(.top, NeuSpace.sm)
                content
                PoweredBy().padding(.horizontal, NeuSpace.xs).padding(.top, NeuSpace.sm)
            }
            .padding(.horizontal, NeuSpace.edge)
            .padding(.bottom, NeuSpace.xl)
        }
        .background(Neu.material.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 一塊凸起面板
struct NeuPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) { content }
            .padding(NeuSpace.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .neuRaised(NeuRadius.panel)
    }
}

/// 選項列：選中＝凹下去（已選）＋打勾；沒選＝凸起（可按）
struct NeuOptionRow: View {
    let title: String
    var detail: String? = nil
    var selected: Bool
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NeuSpace.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NeuFont.ui(NeuType.body, selected)).foregroundStyle(disabled ? Neu.inkSoft : Neu.inkStrong)
                    if let detail {
                        Text(detail).font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.inkMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Neu.inkStrong) }
            }
            .padding(.horizontal, NeuSpace.lg)
            .padding(.vertical, NeuSpace.md)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background {
                if selected {
                    Color.clear.neuDebossed(NeuRadius.card, depth: 0.85)
                } else {
                    Color.clear.neuRaised(NeuRadius.card, lift: 0.55)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// 一個翻譯目標：換對象、移到最前、刪掉
struct TargetDetailView: View {
    let index: Int
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var targets = Translate.targets

    var body: some View {
        NeuPage(title: targets.indices.contains(index) ? targets[index].label : "翻譯目標") {
            if targets.indices.contains(index) {
                let t = targets[index]
                NeuPanel {
                    Text("翻成\(t.lang.label)時的對象").font(NeuFont.ui(NeuType.title, true)).foregroundStyle(Neu.inkStrong)
                    ForEach(Translate.situations(t.lang)) { sit in
                        NeuOptionRow(title: sit.label, detail: sit.hint, selected: sit == t.situation) {
                            var list = targets
                            list[index] = Translate.Target(lang: t.lang, situation: sit)
                            save(list)
                        }
                    }
                    NeuNote(text: "對象決定語氣與怎麼稱呼對方；句尾（ครับ／ค่ะ）與自稱看「我的口吻」。")
                }
                HStack(spacing: NeuSpace.md) {
                    if index > 0 {
                        NeuChip(title: "移到最前") {
                            var list = targets
                            list.insert(list.remove(at: index), at: 0)
                            save(list)
                            dismiss()
                        }
                    }
                    NeuChip(title: "刪掉這個目標") {
                        var list = targets
                        list.remove(at: index)
                        save(list)
                        dismiss()
                    }
                }
            }
        }
    }

    private func save(_ list: [Translate.Target]) {
        Translate.targets = list
        targets = list
        changed()
    }
}

/// 新增翻譯目標：先看語言、再挑對象（每個對象下面一句說明它的語氣）
struct AddTargetView: View {
    let existing: Set<String>
    let add: (Translate.Target) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NeuPage(title: "新增翻譯目標") {
            ForEach([OutputLang.th, .ja, .en]) { l in
                NeuPanel {
                    Text(l.label).font(NeuFont.ui(NeuType.title, true)).foregroundStyle(Neu.inkStrong)
                    ForEach(Translate.situations(l)) { sit in
                        let t = Translate.Target(lang: l, situation: sit)
                        NeuOptionRow(title: sit.label, detail: sit.hint, selected: existing.contains(t.key), disabled: existing.contains(t.key)) {
                            add(t)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct SpeakerView: View {
    @State private var speaker = Translate.speaker

    var body: some View {
        NeuPage(title: "我的口吻") {
            NeuPanel {
                ForEach(SpeakerVoice.allCases) { v in
                    NeuOptionRow(title: v.label, selected: v == speaker) {
                        speaker = v
                        Translate.speaker = v
                    }
                }
                NeuNote(text: "只管句尾與有性別的自稱：泰文的 ครับ（男）／ค่ะ、คะ（女）、正式自稱 ผม／ดิฉัน，日文口語的 僕／私。不指定＝一律用不分男女的說法（泰文聽起來會比較淡）。")
            }
        }
    }
}

struct PolishView: View {
    @State private var modeIndex = PolishMode.allCases.firstIndex(of: Settings.polishMode) ?? 0
    @State private var modelIndex = Settings.claudeModels.firstIndex(of: Settings.claudeModel) ?? 0
    @State private var usePCC = Settings.usePCC
    @State private var claudeTest: String?
    @State private var claudeTesting = false

    private var mode: PolishMode { PolishMode.allCases[modeIndex] }

    var body: some View {
        NeuPage(title: "整理方式") {
            if mode == .claude { MacRelayPanel() }
            NeuPanel {
                NeuSegmented(items: PolishMode.allCases.map(\.label), selection: $modeIndex)
                    .onChange(of: modeIndex) { _, i in Settings.polishMode = PolishMode.allCases[i] }
                NeuNote(text: footer)
                if mode == .claude, !MacRelay.isPaired, !Settings.bridgeURL.isEmpty {
                    NeuSegmented(items: ["Opus 5.5", "Sonnet 5", "Haiku 4.5"], selection: $modelIndex)
                        .onChange(of: modelIndex) { _, i in
                            Settings.claudeModel = Settings.claudeModels[i]
                            claudeTest = nil
                        }
                    HStack {
                        NeuChip(title: claudeTesting ? "測試中…" : "測試連線", enabled: !claudeTesting) {
                            claudeTesting = true
                            claudeTest = nil
                            Task {
                                switch await Polisher.shared.testClaude() {
                                case .success(let (text, secs)):
                                    claudeTest = String(format: "✓ %.1f 秒：", secs) + text
                                case .failure(let e):
                                    claudeTest = "✗ " + e.localizedDescription
                                }
                                claudeTesting = false
                            }
                        }
                        Spacer()
                    }
                    if let t = claudeTest {
                        Text(t).font(NeuFont.ui(NeuType.caption)).foregroundStyle(t.hasPrefix("✓") ? Neu.inkStrong : Neu.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if mode == .apple {
                    Toggle(isOn: $usePCC) {
                        Text("先用 Apple 私有雲模型（需 iOS 27）").font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.inkStrong)
                    }
                    .tint(Neu.inkStrong)
                    .onChange(of: usePCC) { _, v in Settings.usePCC = v }
                    NeuNote(text: appleStatus)
                }
            }
        }
    }

    private var footer: String {
        switch mode {
        case .apple: return "手機上的 Apple 模型整理，免費、離線。"
        case .claude:
            return "用你自己電腦上登入的 Claude／ChatGPT 訂閱（不用 API 金鑰）：配對過的 Mac 優先，連不到會自動改用 Apple，字照樣打得出來。翻譯一律走這條（有語氣）。"
        case .off: return "只做繁體化與全形標點，不改寫任何字。翻譯仍走 Claude 訂閱。"
        }
    }

    private var appleStatus: String {
        var parts: [String] = []
        if #available(iOS 27.0, *) {
            let pcc = PrivateCloudComputeLanguageModel()
            parts.append(pcc.isAvailable ? "私有雲模型：可用" : "私有雲模型：這支手機目前不能用")
        } else {
            parts.append("私有雲模型：要 iOS 27")
        }
        switch SystemLanguageModel.default.availability {
        case .available: parts.append("本機模型：可用")
        case .unavailable(.appleIntelligenceNotEnabled): parts.append("本機模型：Apple Intelligence 沒開")
        case .unavailable(.deviceNotEligible): parts.append("本機模型：這支手機不支援")
        case .unavailable(.modelNotReady): parts.append("本機模型：下載中")
        case .unavailable: parts.append("本機模型：暫時不能用")
        }
        return parts.joined(separator: "・") + "。全部不能用時照樣貼字，只是不整理。"
    }
}

struct KeepAliveView: View {
    private static let options = [0, 60, 30, 15]
    @State private var index = options.firstIndex(of: Settings.keepAliveMinutes) ?? 0

    var body: some View {
        NeuPage(title: "待命時間") {
            NeuPanel {
                NeuSegmented(items: ["不關", "60 分", "30 分", "15 分"], selection: $index)
                    .onChange(of: index) { _, i in Settings.keepAliveMinutes = Self.options[i] }
                NeuNote(text: "待命＝麥克風先開好（畫面上方有橘點），鍵盤才能在原地直接講、不用跳 app；沒在聽的聲音直接丟掉。建議「不關」：打開一次 Talky 之後整天都不用再跳。")
            }
        }
    }
}

struct GlossaryView: View {
    @State private var glossary = Settings.glossary
    @FocusState private var focused: Bool

    var body: some View {
        NeuPage(title: "常用詞") {
            NeuPanel {
                TextEditor(text: $glossary)
                    .font(NeuFont.ui(NeuType.body))
                    .foregroundStyle(Neu.inkStrong)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(NeuSpace.sm)
                    .neuDebossed(NeuRadius.key)
                    .focused($focused)
                    .onChange(of: glossary) { _, v in Settings.glossary = v }
                NeuNote(text: "人名、公司名、專有名詞，用頓號分開。辨識、整理、翻譯都會照這個寫法。")
            }
        }
        .onAppear {
            #if DEBUG
            // 開發用：模擬器裡叫出鍵盤看長相（xcrun simctl launch … -TalkyFocusGlossary）
            if ProcessInfo.processInfo.arguments.contains("-TalkyFocusGlossary") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { focused = true }
            }
            #endif
        }
    }
}

/// 離線翻譯（連不到 Mac 與自架服務時的備援）：Apple 翻譯，下載過的語言才能用
struct OfflineView: View {
    @State private var status: [OutputLang: LanguageAvailability.Status] = [:]
    @State private var downloadConfig: TranslationSession.Configuration?

    var body: some View {
        NeuPage(title: "離線翻譯") {
            NeuPanel {
                ForEach([OutputLang.en, .ja, .th]) { l in
                    HStack {
                        Text(l.label).font(NeuFont.ui(NeuType.body)).foregroundStyle(Neu.inkStrong)
                        Spacer()
                        if let st = status[l] {
                            switch st {
                            case .installed:
                                NeuStatusTag(level: .ready, text: "已下載")
                            case .supported:
                                NeuChip(title: "下載", height: 30) {
                                    downloadConfig = TranslationSession.Configuration(
                                        source: Locale.Language(identifier: OutputLang.zh.appleCode),
                                        target: Locale.Language(identifier: l.appleCode))
                                }
                            case .unsupported:
                                NeuStatusTag(level: .missing, text: "不支援")
                            @unknown default:
                                NeuStatusTag(level: .missing, text: "—")
                            }
                        } else {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, NeuSpace.lg)
                    .frame(height: 48)
                    .neuDebossed(NeuRadius.pill, depth: 0.75)
                }
                NeuNote(text: "平常翻譯走 Claude 訂閱（有語氣）。連不到 Mac 時改用 Apple 翻譯：在手機上翻、不用網路，但只有意思、沒有語氣。都不行時先給你中文、不自動打上，免得中文誤傳給外國朋友。")
            }
        }
        .task { await load() }
        .translationTask(downloadConfig) { session in
            // 系統會跳出下載語言的確認；下載完這個語言就能離線翻
            try? await session.prepareTranslation()
            await load()
        }
    }

    private func load() async {
        var m: [OutputLang: LanguageAvailability.Status] = [:]
        for l in [OutputLang.en, .ja, .th] { m[l] = await Polisher.shared.appleTranslateStatus(l) }
        status = m
    }
}

struct MemoView: View {
    @EnvironmentObject private var memo: Memo
    @State private var copiedID: UUID?

    var body: some View {
        NeuPage(title: "最近 20 句") {
            NeuPanel {
                if memo.entries.isEmpty {
                    NeuNote(text: "還沒有。講過的每一句都會留在這裡（只存在這支手機）。")
                }
                ForEach(memo.entries) { e in
                    Button {
                        UIPasteboard.general.string = e.text
                        copiedID = e.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.timeLabel).font(NeuFont.mark(NeuType.micro, false))
                                Text(pathLabel(e.path, lang: e.lang)).font(NeuFont.ui(NeuType.micro))
                                Spacer()
                                if copiedID == e.id { Text("已複製").font(NeuFont.ui(NeuType.micro, true)) }
                            }
                            .foregroundStyle(Neu.inkSoft)
                            Text(e.text).font(NeuFont.ui(NeuType.body)).foregroundStyle(Neu.inkStrong)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(NeuSpace.md)
                        .neuDebossed(NeuRadius.key, depth: 0.7)
                    }
                    .buttonStyle(.plain)
                }
                if !memo.entries.isEmpty { NeuNote(text: "字沒貼進去也不會白講：點一句就複製。") }
            }
        }
    }
}

/// 你的 Mac：配對狀態、那台 Mac 上 Claude／ChatGPT 登入了沒、用哪一顆、在 Mac 上登入、解除配對
struct MacRelayPanel: View {
    private struct MacStatus {
        let name: String
        let claude: Bool?
        let codex: Bool?
    }

    @State private var pairing = MacRelay.pairing
    @State private var status: MacStatus?
    @State private var error: String?
    @State private var loading = false
    @State private var note: String?
    @State private var brainIndex = ["", "claude", "codex"].firstIndex(of: Settings.macBrain) ?? 0

    var body: some View {
        NeuPanel {
            Text("你的 Mac（用它的訂閱）").font(NeuFont.ui(NeuType.title, true)).foregroundStyle(Neu.inkStrong)
            if let p = pairing {
                HStack {
                    NeuStatusTag(level: status != nil ? .ready : (error != nil ? .missing : .pending), text: tagText(p))
                    Spacer()
                    NeuChip(title: loading ? "連線中…" : "重新連", enabled: !loading, height: 30) { Task { await load() } }
                }
                if let e = error { Text(e).font(NeuFont.ui(NeuType.caption)).foregroundStyle(Neu.warn).fixedSize(horizontal: false, vertical: true) }
                if let s = status {
                    brainRow("Claude（Claude Code）", s.claude, provider: "claude")
                    brainRow("ChatGPT（Codex）", s.codex, provider: "codex")
                    NeuSegmented(items: ["照 Mac 的設定", "Claude", "ChatGPT"], selection: $brainIndex, height: 38)
                        .onChange(of: brainIndex) { _, i in Settings.macBrain = ["", "claude", "codex"][i] }
                }
                if let n = note { NeuNote(text: n) }
                HStack {
                    Spacer()
                    NeuChip(title: "解除配對", height: 30) {
                        MacRelay.unpair()
                        pairing = nil
                        status = nil
                    }
                }
            } else {
                NeuNote(text: "還沒配對。① Mac 上打開 Talky → 設定 → iPhone → 打開　② 用 iPhone 相機掃那個 QR 碼，會自動打開 Talky 配對好。登入 Claude／ChatGPT 都在 Mac 上、走官方登入頁；iPhone 不碰你的帳號。")
                if !Settings.bridgeURL.isEmpty { NeuNote(text: "現在先走：自架的整理服務（Claude 訂閱）。") }
            }
        }
        .task { if pairing != nil { await load() } }
    }

    private func tagText(_ p: MacPairing) -> String {
        if status != nil { return "已連：\(p.name)" }
        if error != nil { return "連不到：\(p.name)" }
        return "連線中：\(p.name)"
    }

    @ViewBuilder private func brainRow(_ title: String, _ state: Bool?, provider: String) -> some View {
        HStack {
            Text(title).font(NeuFont.ui(NeuType.body)).foregroundStyle(Neu.inkStrong)
            Spacer()
            switch state {
            case true?:
                NeuStatusTag(level: .ready, text: "已登入")
            case false?:
                NeuChip(title: "在 Mac 上登入", height: 30) { Task { await login(provider) } }
            case nil:
                NeuStatusTag(level: .missing, text: "Mac 沒裝")
            }
        }
        .padding(.horizontal, NeuSpace.lg)
        .frame(height: 48)
        .neuDebossed(NeuRadius.pill, depth: 0.75)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await MacRelay.call(["op": "status"], timeout: 10)
            status = MacStatus(name: r["name"] as? String ?? "", claude: r["claude"] as? Bool, codex: r["codex"] as? Bool)
            error = nil
        } catch {
            status = nil
            self.error = error.localizedDescription
        }
    }

    private func login(_ provider: String) async {
        do {
            let r = try await MacRelay.call(["op": "login", "provider": provider], timeout: 10)
            note = (r["note"] as? String ?? "Mac 上已經打開登入頁") + "。登入完回來按「重新連」。"
        } catch {
            note = "叫不動 Mac：\(error.localizedDescription)"
        }
    }
}

/// 鍵盤有沒有加、有沒有開完整取用（開了完整取用的鍵盤會在 App Group 留記號）
enum KeyboardCheck {
    static let keyboardID = "ltd.intention.talky.ios.keyboard"
    static var added: Bool {
        (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String])?.contains(keyboardID) ?? false
    }
    static var fullAccess: Bool { Bridge.shared.object(forKey: "keyboardFullAccessAt") != nil }
}
