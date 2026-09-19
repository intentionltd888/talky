// Brains — 「用什麼來整理」的連接層：偵測、帶著裝、帶著登入、拉模型、測試
//
// 目標：介面上一顆按鈕就能接上這台的 CLI（Claude／Ollama／Codex）；
// 沒裝就帶著裝、帶著拿權限，一路到底。
//
// 四種大腦（v1）：
//   claude  ＝這台的 Claude Code CLI（吃使用者自己的訂閱；逐字稿會送到 Anthropic）
//   ollama  ＝這台的 Ollama（http://127.0.0.1:11434，OpenAI 相容端點；全在本機）
//   local   ＝內建的 llama-server＋Qwen3-4B（全在本機；<12GB 記憶體的機器不啟動）
//   off     ＝不整理（只做簡轉繁、全形標點、去幻聽）
// Codex CLI 後來補上，見 CodexCLI.swift。
//
// app 自己不能替使用者登入任何帳號：能做的是「開終端機、貼好指令、輪詢偵測、登入完自動接手」。
// 開終端機走 AppleScript，第一次系統會問「自動化」權限；被拒就退成「複製指令，自己貼」。

import AppKit
import Foundation

// MARK: - 種類與狀態

enum BrainKind: String, CaseIterable, Identifiable {
    case claude, codex, ollama, local, openai, anthropic, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "用你的 Claude（訂閱）"
        case .codex: return "用你的 ChatGPT（訂閱）"
        case .ollama: return "Ollama（本機）"
        case .local: return "不用帳號：內建模型（全在這台電腦）"
        case .openai: return "自填 OpenAI 相容端點"
        case .anthropic: return "自填 Anthropic 金鑰"
        case .off: return "不用帳號：不整理，直接貼"
        }
    }
    /// 一句成本與隱私（每卡都要講清楚）
    var costLine: String {
        switch self {
        case .claude: return "用你的 Claude 訂閱，不另外付錢；講的話會送到 Anthropic 整理；額度用完自動退本機"
        case .codex: return "用你的 ChatGPT 訂閱（Plus／Pro），不另外付錢；裝了 ChatGPT 桌面版就有；講的話會送到 OpenAI"
        case .ollama: return "全在你的電腦上；用你裝好的 Ollama 模型（預設 qwen3:4b，約 2.5GB）"
        case .local: return "不用任何帳號，全在你的電腦上；要下載 2.5GB，記憶體 12GB 以下的機器不會啟動"
        case .openai: return "任何 /v1/chat/completions 端點（OpenAI、Groq、OpenRouter、LM Studio、公司閘道）；逐字稿會送到你填的那台；金鑰存鑰匙圈"
        case .anthropic: return "直接用你的 Anthropic API 金鑰（按量計費）；逐字稿會送到 Anthropic；金鑰存鑰匙圈"
        case .off: return "最快最省電；只做繁體化、標點、去掉幻聽句，直接貼原稿"
        }
    }
    var mode: PolishMode {
        switch self {
        case .claude: return .claudeCLI
        case .codex: return .codex
        case .ollama: return .ollama
        case .local: return .local
        case .openai: return .openai
        case .anthropic: return .anthropic
        case .off: return .off
        }
    }
    /// 精靈與設定主畫面看得到的三顆（0.1.2 減法：太複雜的收起來）：
    /// 訂閱兩顆＋「不用帳號」那顆——記憶體夠＝內建模型、不夠＝不整理。其餘收在「更多選項」。
    /// 排序：Claude 在前。
    static var primary: [BrainKind] { [.claude, .codex, Dictation.lite ? .off : .local] }
    static var more: [BrainKind] { allCases.filter { !primary.contains($0) } }

    static func from(_ m: PolishMode) -> BrainKind {
        switch m {
        case .claudeCLI: return .claude
        case .codex: return .codex
        case .ollama: return .ollama
        case .local: return .local
        case .openai: return .openai
        case .anthropic: return .anthropic
        case .off: return .off
        }
    }
}

struct BrainState: Equatable {
    enum Level: Equatable { case ready, pending, missing }
    var level: Level
    var text: String
    /// 主動作（安裝／登入／下載／啟動）；nil＝沒有要做的
    var actionTitle: String?
    var actionKind: Action?

    enum Action: Equatable { case install, login, launch, pull, download, openSettings }
}

// MARK: - Ollama 客戶端

enum Ollama {
    static let base = "http://127.0.0.1:11434"
    /// 想要的模型（使用者可在 defaults 改 ollamaModel）；實際送請求用 resolvedModel
    static var wantedModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "qwen3:4b" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }
    /// 上次在 /api/tags 對到的實際名稱（例如 qwen3:4b-instruct-2507-q4_K_M）；對不到就退回 wantedModel
    static var model: String {
        UserDefaults.standard.string(forKey: "ollamaResolvedModel") ?? wantedModel
    }
    /// 在已載入清單裡找最接近想要的那個：完全相同 → 同名同尺寸的變體 → nil
    static func resolve(_ names: [String]) -> String? {
        let want = wantedModel.lowercased()
        if let exact = names.first(where: { $0.lowercased() == want || $0.lowercased() == want + ":latest" }) {
            return exact
        }
        let parts = want.split(separator: ":").map(String.init)
        let family = parts[0]
        let size = parts.count > 1 ? parts[1] : ""
        let cand = names.filter { n in
            let l = n.lowercased()
            return l.hasPrefix(family + ":") && (size.isEmpty || l.contains(size))
        }
        return cand.sorted { $0.count < $1.count }.first
    }
    /// 送請求前一定要走這裡：沒對過名稱就打一次 /api/tags 對；對不到就回想要的名稱（讓錯誤訊息講真話）
    static func ensureResolved(force: Bool = false) -> String {
        if !force, let r = UserDefaults.standard.string(forKey: "ollamaResolvedModel") { return r }
        guard let names = tags() else { return wantedModel }
        let r = resolve(names)
        remember(r)
        return r ?? wantedModel
    }
    /// 模型在不在記憶體裡（/api/ps）；不在＝第一句要等它載入（4B 約 20–40 秒）
    static func isLoaded(_ model: String, timeout: TimeInterval = 1.5) -> Bool {
        guard let url = URL(string: base + "/api/ps") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let sem = DispatchSemaphore(value: 0)
        var loaded = false
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data,
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let models = obj["models"] as? [[String: Any]]
            else { return }
            loaded = models.contains { ($0["name"] as? String)?.lowercased() == model.lowercased() }
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 0.5)
        return loaded
    }

    /// 預熱：叫 Ollama 先把模型載進記憶體並留 30 分鐘（選用它、或 app 啟動時模式是它就呼叫）。
    /// 不預熱的話第一句口述要等 20–40 秒，使用者會以為壞了。
    static func warm() {
        DispatchQueue.global(qos: .userInitiated).async {
            let m = ensureResolved()
            guard !isLoaded(m), let url = URL(string: base + "/api/generate") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 180
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": m, "prompt": "", "keep_alive": "30m"])
            let t0 = Date()
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: req) { _, resp, _ in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                TalkyLog.write(String(format: "ollama warm %@ http=%d %.1fs", m, code, Date().timeIntervalSince(t0)))
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 181)
        }
    }

    static func remember(_ resolved: String?) {
        if let r = resolved {
            UserDefaults.standard.set(r, forKey: "ollamaResolvedModel")
        } else {
            UserDefaults.standard.removeObject(forKey: "ollamaResolvedModel")
        }
    }
    static var appInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ollama")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ollama")
    }

    /// 已載入的模型名；nil＝Ollama 沒在跑
    static func tags(timeout: TimeInterval = 1.5) -> [String]? {
        guard let url = URL(string: base + "/api/tags") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let sem = DispatchSemaphore(value: 0)
        var out: [String]?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data,
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let models = obj["models"] as? [[String: Any]]
            else { return }
            out = models.compactMap { $0["name"] as? String }
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 0.5)
        return out
    }

    /// 有沒有可用的模型；有的話順手記住實際名稱（之後送請求就用它，不會 404）
    static func hasModel(_ names: [String]) -> Bool {
        let r = resolve(names)
        remember(r)
        return r != nil
    }

    static func launchApp() {
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        } else {
            _ = TerminalRunner.run("ollama serve")
        }
    }

    static func openDownloadPage() {
        if let u = URL(string: "https://ollama.com/download/mac") { NSWorkspace.shared.open(u) }
    }

    /// 拉模型（/api/pull 串流 NDJSON）。progress：0–1 與一句狀態。
    final class Pull: NSObject, URLSessionDataDelegate {
        private var buffer = Data()
        private let progress: (Double, String) -> Void
        private let done: (String?) -> Void
        private var session: URLSession?
        private var finished = false

        init(progress: @escaping (Double, String) -> Void, done: @escaping (String?) -> Void) {
            self.progress = progress
            self.done = done
        }

        func start(model: String) {
            guard let url = URL(string: Ollama.base + "/api/pull") else {
                done("URL 組裝失敗")
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 3600
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 3600
            let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            session = s
            s.dataTask(with: req).resume()
        }

        func cancel() {
            session?.invalidateAndCancel()
            if !finished {
                finished = true
                done("已取消")
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    continue
                }
                if let e = obj["error"] as? String {
                    if !finished {
                        finished = true
                        DispatchQueue.main.async { self.done(e) }
                    }
                    return
                }
                let status = obj["status"] as? String ?? ""
                let total = (obj["total"] as? Double) ?? 0
                let completed = (obj["completed"] as? Double) ?? 0
                let frac = total > 0 ? min(1, completed / total) : (status == "success" ? 1 : 0)
                DispatchQueue.main.async { self.progress(frac, status) }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async { self.done(error?.localizedDescription) }
        }
    }
}

// MARK: - 開終端機（AppleScript；需「自動化」權限）

enum TerminalRunner {
    /// 回傳 true＝終端機已打開並執行；false＝失敗（呼叫端退成複製指令）
    /// 先走 .command 檔（NSWorkspace open → 終端機自己執行，**不需要「自動化」權限**，第一次也不會跳系統問窗）；
    /// 失敗才退 AppleScript（要自動化權限）。
    @discardableResult
    static func run(_ command: String) -> Bool {
        let dir = SharedPaths.support.appendingPathComponent("terminal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("talky-\(Int(Date().timeIntervalSince1970)).command")
        let script = "#!/bin/zsh\nclear\necho '── Talky：照著下面的指示做，做完可以關掉這個視窗 ──'\n\(command)\n"
        if (try? script.write(to: f, atomically: true, encoding: .utf8)) != nil {
            chmod(f.path, 0o755)
            if NSWorkspace.shared.open(f) { return true }
            TalkyLog.write("terminal .command open fail, fallback to AppleScript")
        }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"", with: "\\\"")
        let src = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        var err: NSDictionary?
        let ok = NSAppleScript(source: src)?.executeAndReturnError(&err) != nil
        if !ok { TalkyLog.write("terminal run fail: \(err?.description ?? "?")") }
        return ok
    }

    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

// MARK: - 連接動作與狀態（每種大腦一路到底）

enum Brains {
    /// Claude Code 官方原生安裝（不需 Node）。登入走 ClaudeLogin（app 內），退路才是終端機 `claude auth login`。
    /// defaults `claudeInstallCommand` 可覆寫（測試鉤；或公司鏡像）
    static var claudeInstallCommand: String {
        UserDefaults.standard.string(forKey: "claudeInstallCommand") ?? "curl -fsSL https://claude.ai/install.sh | bash"
    }
    static let claudeLoginCommand = "claude auth login"

    /// 給「貼給你的 AI」那扇門的一段話。
    /// 自足版：AGENTS.md 隨 app 裝在包內，不指向使用者拿不到的 repo；
    /// 把 AI 做不到的兩個權限、訂閱優先、最後親手驗收都寫在話裡，AI 沒讀到檔也知道終點是什麼。
    static let agentsFilePath = "/Applications/Talky.app/Contents/Resources/AGENTS.md"
    static let pasteToYourAI = """
        我裝了 Talky（Mac 的繁體中文語音輸入法，開源）。請在這台 Mac 上一步一步帶我把它接好，做到「我在任何文字框連按兩下右 ⌘ 講一句話，整理好的字貼進游標處」為止。
        完整步驟在 \(agentsFilePath)，先讀它。重點：
        1. 先跑 /Applications/Talky.app/Contents/MacOS/Talky --doctor 看缺什麼，照它說的補。
        2. 「麥克風」和「輔助使用」兩個權限只有我本人能按，請告訴我到哪裡按；輔助使用沒開的話快捷鍵完全不會動。
        3. 整理大腦優先用我已經有的訂閱：Claude Code 或 ChatGPT 桌面版（Codex），不要用 API 金鑰；兩個都沒有就選內建本機模型或 Ollama。
        4. 最後請我親手打開備忘錄、連按兩下右 ⌘ 講一句，字貼進去才算完成，再把 --doctor 的結果貼給我看。
        """

    /// 精靈替人選（0.1.2）：使用者自己選過就不動；否則 ChatGPT 登入 → Claude 登入 → 內建（記憶體夠）→ 不整理。
    /// 病史＝舊預設「裝著 claude 就選它」：claude 裝了但沒登入時，整理一直失敗退原稿，使用者會以為 app 壞了。
    /// 會打 `codex login status`／`claude auth status`（各 0.3 秒）：請在背景執行緒呼叫。
    @discardableResult
    static func autoPick() -> BrainKind {
        if UserDefaults.standard.string(forKey: "polishMode") != nil { return BrainKind.from(PolishMode.current) }
        let k: BrainKind
        // Claude 優先：兩個都登入時選 Claude
        if ClaudeCLI.available, ClaudeCLI.authStatus()?.loggedIn == true {
            k = .claude
        } else if CodexCLI.available, CodexCLI.loggedIn() == true {
            k = .codex
        } else {
            k = Dictation.lite ? .off : .local
        }
        select(k)
        TalkyLog.write("brain autopick → \(k.rawValue)")
        // 選了內建而且聽寫模型已在（例如借 Hearby 的）：直接接著下載整理模型；聽寫模型還在下載的話由 AppState 排在它後面
        if k == .local, !LocalLLM.modelReady, TextUtil.whisperModelPath() != nil {
            DispatchQueue.main.async { AppState.shared.downloadPolishModel() }
        }
        return k
    }

    /// 「為什麼是這顆」一句（精靈第 3 步）
    static func pickReason(_ k: BrainKind) -> String {
        switch k {
        case .codex: return "這台有 ChatGPT 而且登入了：用你的訂閱，不另外付錢。"
        case .claude: return "這台有 Claude Code 而且登入了：用你的訂閱，不另外付錢。"
        case .local: return "你沒有 ChatGPT 或 Claude 的訂閱：用內建模型，全在這台電腦上，不用帳號。"
        case .off: return "這台記憶體 \(Dictation.physicalMemoryGB)GB 不夠跑內建模型：字會直接貼、只做繁體與標點。有訂閱的話按「換一個」。"
        case .ollama: return "用你裝好的 Ollama。"
        case .openai, .anthropic: return "用你自己填的金鑰。"
        }
    }

    /// 目前狀態（會打一次 Ollama 的本機端點，約 <1.5 秒；請在背景執行緒呼叫）
    static func state(_ k: BrainKind) -> BrainState {
        switch k {
        case .off:
            return BrainState(level: .ready, text: "不需要設定", actionTitle: nil, actionKind: nil)
        case .openai:
            if Endpoints.openAIFilled {
                return BrainState(
                    level: .ready, text: "已填（\(Endpoints.openAIModel) @ \(Endpoints.host(Endpoints.openAIBase))）",
                    actionTitle: nil, actionKind: nil)
            }
            return BrainState(level: .missing, text: "還沒填端點與模型", actionTitle: nil, actionKind: nil)
        case .anthropic:
            if Endpoints.anthropicFilled {
                return BrainState(
                    level: .ready, text: "已填金鑰（\(Endpoints.anthropicModel)）", actionTitle: nil, actionKind: nil)
            }
            return BrainState(level: .missing, text: "還沒填金鑰", actionTitle: nil, actionKind: nil)
        case .local:
            if Dictation.lite {
                return BrainState(
                    level: .missing, text: "這台記憶體 \(Dictation.physicalMemoryGB)GB，不啟動本機整理",
                    actionTitle: nil, actionKind: nil)
            }
            if LocalLLM.modelReady {
                return BrainState(level: .ready, text: "模型已在", actionTitle: nil, actionKind: nil)
            }
            return BrainState(
                level: .missing, text: "還沒下載整理模型（2.5GB）", actionTitle: "下載", actionKind: .download)
        case .claude:
            guard ClaudeCLI.available else {
                return BrainState(
                    level: .missing, text: "這台沒有 Claude Code", actionTitle: "安裝 Claude Code",
                    actionKind: .install)
            }
            // 登入與否問 `claude auth status`（0.3 秒、不打模型），不再拿整理探針猜
            guard let st = ClaudeCLI.authStatus() else {
                return BrainState(
                    level: .pending, text: "已安裝，還沒確認登入", actionTitle: "登入", actionKind: .login)
            }
            guard st.loggedIn else {
                return BrainState(
                    level: .pending, text: "已安裝，還沒登入（按「登入」，在 app 裡就能完成）", actionTitle: "登入",
                    actionKind: .login)
            }
            if ClaudeCLI.coolingDown {
                return BrainState(
                    level: .pending, text: "已登入（\(st.subscriptionLabel)），上次整理失敗先走本機——按「測試」重試",
                    actionTitle: nil, actionKind: nil)
            }
            return BrainState(
                level: .ready, text: "已連接（\(st.subscriptionLabel)，\(ClaudeCLI.model)）", actionTitle: nil,
                actionKind: nil)
        case .codex:
            guard CodexCLI.available else {
                return BrainState(
                    level: .missing, text: "還沒接上", actionTitle: "接上 ChatGPT",
                    actionKind: .install)
            }
            switch CodexCLI.loggedIn() {
            case .some(true):
                return BrainState(
                    level: .ready, text: "已連接（\(CodexCLI.viaChatGPTApp ? "ChatGPT 桌面版" : "codex 指令")）",
                    actionTitle: nil, actionKind: nil)
            default:
                return BrainState(level: .pending, text: "還沒登入", actionTitle: "登入 ChatGPT", actionKind: .login)
            }
        case .ollama:
            if let names = Ollama.tags() {
                if Ollama.hasModel(names) {
                    return BrainState(level: .ready, text: "已連接（\(Ollama.model)）", actionTitle: nil, actionKind: nil)
                }
                return BrainState(
                    level: .pending, text: "Ollama 在跑，還沒有 \(Ollama.wantedModel)", actionTitle: "下載模型",
                    actionKind: .pull)
            }
            if Ollama.appInstalled {
                return BrainState(level: .pending, text: "已安裝，沒在跑", actionTitle: "啟動 Ollama", actionKind: .launch)
            }
            return BrainState(level: .missing, text: "這台沒有 Ollama", actionTitle: "下載 Ollama", actionKind: .install)
        }
    }

    /// 執行主動作。回傳給使用者看的一句話（成功或退路）。
    static func perform(_ k: BrainKind, _ a: BrainState.Action) -> String {
        switch (k, a) {
        case (.claude, .install):
            // app 內裝（0.1.2；不開終端機、不要權限）；bash 起不來才退終端機／複製指令
            let started = Thread.isMainThread ? ClaudeInstall.shared.start() : DispatchQueue.main.sync { ClaudeInstall.shared.start() }
            if started { return "" }
            if TerminalRunner.run(claudeInstallCommand) {
                return "終端機已打開，裝完回來這裡會自動偵測到。"
            }
            TerminalRunner.copy(claudeInstallCommand)
            return "打不開終端機，指令已複製：貼到終端機執行。"
        case (.claude, .login):
            ClaudeCLI.resetCooldown()
            ClaudeCLI.resetAuthCache()
            // 先走 app 內登入（不開終端機、不要任何權限）；起不來才退終端機
            let started = Thread.isMainThread ? ClaudeLogin.shared.start() : DispatchQueue.main.sync { ClaudeLogin.shared.start() }
            if started { return "" }
            let cmd = "\"\(ClaudeCLI.binaryPath() ?? "claude")\" auth login"
            if TerminalRunner.run(cmd) {
                return "終端機已打開：跟著它登入（會開瀏覽器），完成後回來這裡會自動打勾。"
            }
            TerminalRunner.copy(cmd)
            return "打不開終端機，指令已複製：貼到終端機執行完成登入。"
        case (.codex, .install):
            // app 內下載官方獨立執行檔（不需 Node、不需 ChatGPT 桌面版），裝好自動接登入
            let started = Thread.isMainThread ? CodexInstall.shared.start() : DispatchQueue.main.sync { CodexInstall.shared.start() }
            if started { return "" }
            if let u = URL(string: "https://chatgpt.com/download") { NSWorkspace.shared.open(u) }
            return "下載起不來：已打開 ChatGPT 桌面版下載頁，裝好登入後回來會自動偵測到。"
        case (.codex, .login):
            CodexCLI.resetLoginCache()
            // app 內登入：codex 自己開瀏覽器，登入完自動綁定
            let started = Thread.isMainThread ? CodexLogin.shared.start() : DispatchQueue.main.sync { CodexLogin.shared.start() }
            if started { return "" }
            let cmd = "\"\(CodexCLI.binaryPath() ?? "codex")\" login"
            if TerminalRunner.run(cmd) {
                return "終端機已打開：跟著它登入 ChatGPT（會開瀏覽器），完成後按「測試」。"
            }
            TerminalRunner.copy(cmd)
            return "打不開終端機，指令已複製：貼到終端機執行完成登入。"
        case (.ollama, .install):
            Ollama.openDownloadPage()
            return "已打開 Ollama 下載頁：裝好、打開它，回來按「啟動」或「下載模型」。"
        case (.ollama, .launch):
            Ollama.launchApp()
            return "正在啟動 Ollama，幾秒後會自動偵測。"
        case (.ollama, .pull):
            return "開始下載 \(Ollama.wantedModel)…"
        case (.local, .download):
            AppState.shared.downloadPolishModel()
            return "開始下載整理模型（2.5GB）。"
        default:
            return ""
        }
    }

    /// 測試：用固定台詞真跑一次這顆大腦。回傳（結果、秒數、錯誤）。
    static let testSentence = "呃就是那個我們明天下午三點要開會嘛,啊不對是四點,對對對。"
    static func test(_ k: BrainKind) -> (String?, Double, String?) {
        let t0 = Date()
        let r = TalkyServers.shared.polishVia(k, raw: testSentence)
        let secs = Date().timeIntervalSince(t0)
        if k == .claude {
            ClaudeCLI.lastProbe = (r.0 != nil)
            ClaudeCLI.resetAuthCache()
        }
        if k == .codex { CodexCLI.resetLoginCache() }
        return (r.0, secs, r.1)
    }
}
