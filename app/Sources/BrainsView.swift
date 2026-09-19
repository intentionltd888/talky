// BrainsView — 「用什麼來整理」的連接面（精靈第 3 步「換一個」與設定→進階共用）
//
// 每一列＝一顆大腦：選用點、名稱、成本與隱私一句、狀態燈（未安裝／待處理／已連接）、
// 主動作鈕（安裝／登入／啟動／下載模型）、「測試」鈕、一行回饋。
// 狀態每 3 秒在背景重算一次（Ollama 會打一次本機端點，<1.5 秒），所以「裝好回來會自動偵測到」。

import AppKit
import SwiftUI

extension Brains {
    /// 選用某顆大腦：寫設定、重整引擎、重探 Claude
    static func select(_ k: BrainKind) {
        PolishMode.set(k.mode)
        DispatchQueue.global(qos: .userInitiated).async {
            TalkyServers.shared.startAll()
            ClaudeCLI.resetCooldown()
            ClaudeCLI.probeInBackground(reason: "brain-selected")
            if k == .ollama { Ollama.warm() }
            if k == .codex { CodexCLI.resetLoginCache() }
        }
    }
}

struct BrainRow: View {
    let kind: BrainKind
    @Binding var selected: BrainKind
    var compact = false

    @ObservedObject private var app = AppState.shared
    @ObservedObject private var login = ClaudeLogin.shared
    @ObservedObject private var install = ClaudeInstall.shared
    @ObservedObject private var codexInstall = CodexInstall.shared
    @ObservedObject private var codexLogin = CodexLogin.shared
    @State private var loginCode = ""
    @State private var state = BrainState(level: .pending, text: "檢查中…", actionTitle: nil, actionKind: nil)
    @State private var message = ""
    @State private var testing = false
    @State private var pull: Ollama.Pull?
    @State private var pullFraction: Double = 0
    @State private var pullStatus = ""
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var isSelected: Bool { selected == kind }

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            HStack(alignment: .top, spacing: NeuSpace.md) {
                // 圓點只是指示；整列都能點（下面 .onTapGesture）。病史＝以前只有這 16pt 的圓點是鈕，
                // 病史：以前點名稱沒反應，沒辦法用點的切換
                ZStack {
                    Circle().strokeBorder(isSelected ? Neu.inkStrong : Neu.inkSoft, lineWidth: 1.2)
                        .frame(width: 18, height: 18)
                    if isSelected { Circle().fill(Neu.inkStrong).frame(width: 9, height: 9) }
                }
                .padding(.top, 1)
                .accessibilityLabel(isSelected ? "已選用" : "選用 \(kind.title)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title).font(NeuFont.ui(NeuType.body, isSelected)).foregroundColor(Neu.inkStrong)
                    if !compact {
                        Text(kind.costLine).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                NeuStatusTag(level: tagLevel, text: state.text)
                    .frame(maxWidth: 190, alignment: .trailing)
            }
            if kind != .off {
                HStack(spacing: NeuSpace.sm) {
                    if let t = state.actionTitle, let a = state.actionKind, pull == nil, !(kind == .local && app.downloadFraction != nil),
                        !(kind == .claude && install.running), !(kind == .codex && (codexInstall.running || codexLogin.running))
                    {
                        NeuChip(title: t) { perform(a) }
                    }
                    NeuChip(title: testing ? "測試中…" : "測試", enabled: !testing && state.level != .missing) { runTest() }
                    if !message.isEmpty {
                        Text(message).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28)
                if pull != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        NeuGroove(fill: CGFloat(pullFraction), height: 10)
                        HStack {
                            Text("\(Ollama.wantedModel) \(Int(pullFraction * 100))%　\(pullStatus)")
                                .font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                            Spacer()
                            NeuChip(title: "取消") { pull?.cancel() }
                        }
                    }
                    .padding(.leading, 28)
                }
                if kind == .openai || kind == .anthropic {
                    EndpointFields(kind: kind, onSaved: refresh).padding(.leading, 28)
                }
                // Codex 安裝卡／登入卡（0.1.3 build 11）：下載進度 → 自動接登入 → 登入成功自動綁定
                if kind == .codex, codexInstall.running || codexInstall.failed {
                    VStack(alignment: .leading, spacing: NeuSpace.sm) {
                        NeuNote(text: codexInstall.note)
                        if codexInstall.running { NeuGroove(fill: CGFloat(codexInstall.fraction), height: 10) }
                        HStack(spacing: NeuSpace.sm) {
                            if codexInstall.running { NeuChip(title: "取消") { codexInstall.cancel() } }
                            Spacer()
                        }
                    }
                    .padding(NeuSpace.md)
                    .neuDebossed(NeuRadius.card, depth: 0.7)
                    .padding(.leading, 28)
                }
                if kind == .codex, codexLogin.running || (!codexLogin.note.isEmpty && codexLogin.succeeded) {
                    VStack(alignment: .leading, spacing: NeuSpace.sm) {
                        NeuNote(text: codexLogin.note)
                        if codexLogin.running {
                            HStack(spacing: NeuSpace.sm) {
                                if codexLogin.url != nil { NeuChip(title: "瀏覽器沒開？再開一次") { codexLogin.openBrowserAgain() } }
                                NeuChip(title: "取消") { codexLogin.cancel() }
                                Spacer()
                            }
                        }
                    }
                    .padding(NeuSpace.md)
                    .neuDebossed(NeuRadius.card, depth: 0.7)
                    .padding(.leading, 28)
                    .onChange(of: codexLogin.succeeded) { _, ok in if ok { message = ""; refresh() } }
                }
                // Claude 安裝卡（0.1.2，app 內跑官方腳本）：進度一行＋取消；失敗留一行＋「複製指令」退路
                if kind == .claude, install.running || install.failed {
                    VStack(alignment: .leading, spacing: NeuSpace.sm) {
                        NeuNote(text: install.note)
                        HStack(spacing: NeuSpace.sm) {
                            if install.running {
                                NeuChip(title: "取消") { install.cancel() }
                            } else {
                                NeuChip(title: "複製指令") { TerminalRunner.copy(Brains.claudeInstallCommand) }
                            }
                            Spacer()
                        }
                    }
                    .padding(NeuSpace.md)
                    .neuDebossed(NeuRadius.card, depth: 0.7)
                    .padding(.leading, 28)
                    .onChange(of: install.succeeded) { _, ok in if ok { refresh() } }
                }
                // Claude 登入卡（app 內完成，不開終端機）：瀏覽器登入 → 需要的話貼代碼 → 每 2 秒自動確認
                if kind == .claude, login.running || (!login.note.isEmpty && login.succeeded) {
                    VStack(alignment: .leading, spacing: NeuSpace.sm) {
                        NeuNote(text: login.note)
                        if login.running, login.needsCode {
                            HStack(spacing: NeuSpace.sm) {
                                TextField("貼上瀏覽器給你的代碼", text: $loginCode)
                                    .textFieldStyle(.plain)
                                    .font(NeuFont.ui(NeuType.caption))
                                    .foregroundColor(Neu.inkStrong)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .neuDebossed(10, depth: 0.8)
                                    .onSubmit { login.submit(code: loginCode) }
                                NeuChip(title: "送出", enabled: !loginCode.trimmingCharacters(in: .whitespaces).isEmpty) {
                                    login.submit(code: loginCode)
                                }
                            }
                        }
                        if login.running {
                            HStack(spacing: NeuSpace.sm) {
                                if login.url != nil { NeuChip(title: "瀏覽器沒開？再開一次") { login.openBrowserAgain() } }
                                NeuChip(title: "取消") { login.cancel() }
                                Spacer()
                            }
                        }
                    }
                    .padding(NeuSpace.md)
                    .neuDebossed(NeuRadius.card, depth: 0.7)
                    .padding(.leading, 28)
                    .onChange(of: login.succeeded) { _, ok in
                        if ok {
                            loginCode = ""
                            message = ""
                            refresh()
                        }
                    }
                }
                if kind == .local, let f = app.downloadFraction {
                    VStack(alignment: .leading, spacing: 4) {
                        NeuGroove(fill: CGFloat(f), height: 10)
                        Text(String(format: "下載中 %.0f%%", f * 100)).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(NeuSpace.md)
        .neuDebossed(NeuRadius.card, depth: isSelected ? 0.95 : 0.55)
        .contentShape(Rectangle())
        // 整列可點：列內的按鈕與欄位自己接自己的點擊（子層手勢優先），點到其他任何地方＝選用這顆
        .onTapGesture { if !isSelected { choose() } }
        // 旁白／輔助工具：整列當一顆鈕（onTapGesture 不會自動進無障礙樹）
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isSelected ? "已選用 \(kind.title)" : "選用 \(kind.title)")
        .accessibilityAction { if !isSelected { choose() } }
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private var tagLevel: NeuStatusTag.Level {
        switch state.level {
        case .ready: return .ready
        case .pending: return .pending
        case .missing: return .missing
        }
    }

    private func choose() {
        selected = kind
        Brains.select(kind)
        refresh()
    }

    private func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let st = Brains.state(kind)
            DispatchQueue.main.async {
                if st != self.state { self.state = st }
            }
        }
    }

    private func perform(_ a: BrainState.Action) {
        message = Brains.perform(kind, a)
        if kind == .ollama, a == .pull {
            let p = Ollama.Pull(
                progress: { f, s in
                    pullFraction = f
                    pullStatus = s
                },
                done: { err in
                    pull = nil
                    message = err.map { "下載失敗：\($0)" } ?? "模型下載完成"
                    refresh()
                })
            pull = p
            pullFraction = 0
            pullStatus = "連線中…"
            p.start(model: Ollama.wantedModel)
        }
    }

    private func runTest() {
        testing = true
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let (text, secs, err) = Brains.test(kind)
            DispatchQueue.main.async {
                testing = false
                if let t = text, !t.isEmpty {
                    // 只顯示「測試成功」：秒數與句子一般使用者不會看
                    message = "測試成功"
                    TalkyLog.write(String(format: "brain test %@ ok %.1fs: %@", kind.rawValue, secs, t))
                } else {
                    message = "沒成功：\(err ?? "沒有回應")"
                }
                refresh()
            }
        }
    }
}

/// 自填端點的三個欄位（端點／模型／金鑰）＋儲存；金鑰進鑰匙圈
struct EndpointFields: View {
    let kind: BrainKind
    var onSaved: () -> Void
    @State private var base = ""
    @State private var model = ""
    @State private var key = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            field("端點", $base, placeholder: kind == .openai ? "https://api.openai.com/v1" : "https://api.anthropic.com")
            field("模型", $model, placeholder: kind == .openai ? "gpt-4o-mini" : "claude-sonnet-5")
            field("金鑰", $key, placeholder: kind == .openai ? "sk-…（本機端點可留空）" : "sk-ant-…", secure: true)
            HStack(spacing: NeuSpace.sm) {
                NeuChip(title: "儲存") { save() }
                if !note.isEmpty {
                    Text(note).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                }
                Spacer()
            }
        }
        .onAppear(perform: load)
    }

    private func field(_ label: String, _ text: Binding<String>, placeholder: String, secure: Bool = false)
        -> some View
    {
        HStack(spacing: NeuSpace.sm) {
            Text(label).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid).frame(width: 30, alignment: .leading)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(NeuFont.ui(NeuType.caption))
            .foregroundColor(Neu.inkStrong)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .neuDebossed(10, depth: 0.8)
        }
    }

    private func load() {
        if kind == .openai {
            base = Endpoints.openAIBase
            model = Endpoints.openAIModel
            key = Endpoints.openAIKey
        } else {
            base = Endpoints.anthropicBase
            model = Endpoints.anthropicModel
            key = Endpoints.anthropicKey
        }
    }

    private func save() {
        if kind == .openai {
            Endpoints.openAIBase = base
            Endpoints.openAIModel = model
            Endpoints.openAIKey = key
        } else {
            Endpoints.anthropicBase = base
            Endpoints.anthropicModel = model
            Endpoints.anthropicKey = key
        }
        note = "已存，按「測試」試一句"
        onSaved()
    }
}

/// 「貼給你的 AI」那扇門：一顆鈕把 Brains.pasteToYourAI 放進剪貼簿。
/// 放在設定 → 進階的最上面；0.1.2 起精靈只在收尾頁「還缺 N 樣」時露出（阿嬤的路上不出現）。
struct PasteToAIChip: View {
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            NeuNote(text: "不想自己弄？複製這段貼給你的 Claude 或 ChatGPT，它會帶你做完。")
            HStack(spacing: NeuSpace.sm) {
                NeuChip(title: copied ? "已複製，去貼給你的 AI" : "複製這段貼給你的 AI") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Brains.pasteToYourAI, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { copied = false }
                }
                Spacer()
            }
        }
    }
}

/// 大腦清單（0.1.2 減法）：三顆可見（ChatGPT／Claude／不用帳號）＋「更多選項」收其餘（Ollama、不整理或內建、自填金鑰）。
/// 選了收起來的那顆會自動展開。onChange＝精靈第 3 步用來刷新「已選好」那張卡。
struct BrainsList: View {
    @State private var selected: BrainKind = BrainKind.from(PolishMode.current)
    var compact = false
    var onChange: ((BrainKind) -> Void)? = nil
    @State private var showMore = BrainKind.more.contains(BrainKind.from(PolishMode.current))

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) {
            ForEach(BrainKind.primary) { k in
                BrainRow(kind: k, selected: $selected, compact: compact)
            }
            HStack(spacing: NeuSpace.sm) {
                NeuChip(title: showMore ? "收起更多選項" : "更多選項（Ollama、自填金鑰…給會用的人）") {
                    withAnimation(NeuMotion.ui) { showMore.toggle() }
                }
                Spacer()
            }
            if showMore {
                ForEach(BrainKind.more) { k in
                    BrainRow(kind: k, selected: $selected, compact: compact)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // 在 ScrollView 裡也要跟上面的卡一樣寬（不然往下滑會變很窄）
        .onChange(of: selected) { _, k in onChange?(k) }
    }
}
