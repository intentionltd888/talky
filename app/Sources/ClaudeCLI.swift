// ClaudeCLI — 潤飾第一檔位：這台電腦上的 Claude Code CLI（用使用者自己的訂閱額度）
//
// 前提＝這台真的裝著 `claude` 而且登入過（終端機跑過一次 claude 登入）。沒登入時誠實報錯，
// 不靜默降級：第一次失敗會進冷卻（預設 600 秒），冷卻期直接退本機模型——
// 否則每句口述都要等滿逾時才貼得出字。
//
// 可調參數（都在 defaults，domain＝ltd.intention.talky，一般人不用碰）：
//   claudePath        自訂執行檔位置
//   claudeConfigDir   帶給 CLI 的 CLAUDE_CONFIG_DIR（測試登入流程用；一般人不用碰）
//   claudeModel       預設 opus（opus 別名＝該帳號最新的 Opus）
//   claudeEffort      預設 low
//   claudeTimeout     預設 45（秒）
//   claudeProbeTimeout 背景探針自己的逾時，預設 12（秒）；它握著 warmLock，拖久了口述要跟著等
//   claudeCooldown    預設 600（秒）
//   claudeExtraArgs   空白分隔的額外參數
//   claudeNoWarm      YES＝關掉常駐會話（除錯用，每句冷啟）
//   claudeWarmTurns   常駐會話跑幾句就重生，預設 40
//
// 隔離旗標（每次呼叫都帶）：
// ・--tools ""：純文字整理，永不動任何工具
// ・--no-session-persistence：每句口述不留 session 檔
// ・--strict-mcp-config：不啟動任何 MCP 伺服器（否則使用者設定裡的 MCP 會被全拉起來，
//   等授權會把一次潤飾拖到分鐘級）
// ・--setting-sources ""：不讀 user／project／local 設定（hook、skills 一律不載）
// ・中性工作目錄：不在使用者的專案夾啟動（既拖慢啟動，也是 prompt 注入面）
// ・環境剝除 CLAUDE*／ANTHROPIC*：從某些終端環境啟動 app 時會繼承宿主的認證代理變數，
//   子行程等宿主授權＝永久卡住

import Foundation

enum ClaudeCLI {
    /// 這台找得到執行檔＝檔位可用
    static var available: Bool { binaryPath() != nil }

    /// 最近一次探針／口述的結果（nil＝還沒試過）：連接面的狀態燈靠這個，不另外多打
    static var lastProbe: Bool? {
        get { UserDefaults.standard.object(forKey: "claudeLastProbeOK") as? Bool }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "claudeLastProbeOK") } else {
                UserDefaults.standard.removeObject(forKey: "claudeLastProbeOK")
            }
        }
    }

    /// 預設模型依「這台登入的是哪種方案」決定（避免把使用者的額度用爆）：
    /// Max＝額度寬，用 opus；其他方案（Pro／Team／未知）一律 sonnet——實測潤飾品質只差在
    /// 長句偶爾漏掉否定對比，遠比「把人家自己的 Claude Code 額度吃光」小。使用者要改就設 claudeModel。
    /// 解析一次就記住：每句都重算會讓 model 值抖動，而 model 變動＝常駐會話重生。
    private static var resolvedDefaultModel: String?
    static var defaultModel: String {
        if let m = resolvedDefaultModel { return m }
        guard let st = authStatus(), st.loggedIn else { return "sonnet" }  // 還不知道＝先保守，不快取
        let m = (st.subscription ?? "").lowercased() == "max" ? "opus" : "sonnet"
        resolvedDefaultModel = m
        TalkyLog.write("claude default model = \(m)（方案 \(st.subscriptionLabel)）")
        return m
    }
    static var model: String { UserDefaults.standard.string(forKey: "claudeModel") ?? defaultModel }

    /// 找 claude 執行檔（病史：裝在 ~/.local/bin 但不在 app 的 PATH 上）：
    /// ①使用者指定 ②官方原生安裝與常見套件管理器路徑 ③nvm／npm 全域 ④登入 shell 的 PATH（`command -v claude`，一次快取）
    /// ⑤Claude 桌面版自帶的那顆（~/Library/Application Support/Claude/claude-code/<版本>/claude.app）——最後才用
    private static var shellLookupCache: String??
    static func binaryPath() -> String? {
        var candidates: [String] = []
        if let p = UserDefaults.standard.string(forKey: "claudePath"), !p.isEmpty {
            candidates.append((p as NSString).expandingTildeInPath)
        }
        let home = NSHomeDirectory()
        candidates += [
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
            home + "/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.npm-global/bin/claude",
            home + "/.bun/bin/claude",
            home + "/.volta/bin/claude",
        ]
        let fm = FileManager.default
        if let versions = try? fm.contentsOfDirectory(atPath: home + "/.nvm/versions/node") {
            for v in versions.sorted().reversed() { candidates.append(home + "/.nvm/versions/node/\(v)/bin/claude") }
        }
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return hit }
        if let s = shellLookup(), fm.isExecutableFile(atPath: s) { return s }
        let desk = home + "/Library/Application Support/Claude/claude-code"
        if let vs = try? fm.contentsOfDirectory(atPath: desk) {
            for v in vs.sorted { $0.compare($1, options: .numeric) == .orderedDescending } {
                let p = desk + "/\(v)/claude.app/Contents/MacOS/claude"
                if fm.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    /// 登入 shell 的 PATH 裡有沒有 claude（使用者自己的 .zshrc 加的路徑）；3 秒逾時、整個 app 生命週期只跑一次
    private static func shellLookup() -> String? {
        if let c = shellLookupCache { return c }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "command -v claude"]
        p.environment = cleanEnvironment()
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var result: String?
        if (try? p.run()) != nil {
            let group = DispatchGroup()
            group.enter()
            var data = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                data = out.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            if group.wait(timeout: .now() + 3) == .timedOut { p.terminate() } else { p.waitUntilExit() }
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if p.terminationStatus == 0, s.hasPrefix("/") { result = s }
        }
        shellLookupCache = .some(result)
        return result
    }

    // ── 登入狀態（`claude auth status`，JSON；連接面每 3 秒問一次所以快取 20 秒）──
    struct AuthStatus {
        let loggedIn: Bool
        let subscription: String?
        let email: String?
        var subscriptionLabel: String {
            switch (subscription ?? "").lowercased() {
            case "max": return "Max"
            case "pro": return "Pro"
            case "team": return "Team"
            case "enterprise": return "Enterprise"
            case "": return "已登入"
            default: return subscription!
            }
        }
    }
    private static var authCache: (Date, AuthStatus?)?
    private static let authLock = NSLock()
    static func authStatus(force: Bool = false) -> AuthStatus? {
        guard let bin = binaryPath() else { return nil }
        authLock.lock()
        if !force, let (t, v) = authCache, Date().timeIntervalSince(t) < 20 {
            authLock.unlock()
            return v
        }
        authLock.unlock()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["auth", "status"]
        p.environment = environment()
        p.currentDirectoryURL = neutralCwd()
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let group = DispatchGroup()
        group.enter()
        var data = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + 8) == .timedOut {
            p.terminate()
            return nil
        }
        p.waitUntilExit()
        var st: AuthStatus?
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            st = AuthStatus(
                loggedIn: obj["loggedIn"] as? Bool ?? false, subscription: obj["subscriptionType"] as? String,
                email: obj["email"] as? String)
        }
        authLock.lock()
        authCache = (Date(), st)
        authLock.unlock()
        return st
    }
    static func resetAuthCache() {
        authLock.lock()
        authCache = nil
        resolvedDefaultModel = nil  // 換帳號／重新登入＝方案可能不同，預設模型要重算
        authLock.unlock()
    }

    /// 便宜的健康檢查：這台的 claude 還在登入狀態嗎？
    /// `claude auth status` 實測 0.13 秒、不花任何額度、不佔常駐會話的 turn，
    /// 而舊的「打一句『好』去撞牆」探針要 1.5 秒＋1541 tokens 才推測出同一件事。
    /// nil＝問不出來（CLI 沒回應／沒裝），當成「還能試」，不要因為問不到就擋住口述。
    static var loggedInNow: Bool {
        guard binaryPath() != nil else { return false }
        guard let st = authStatus() else { return true }
        return st.loggedIn
    }

    /// CLI 是否支援 --effort／--system-prompt（版本相依）：--help 探一次、整個 app 生命週期快取
    private static let helpText: String = {
        guard let bin = binaryPath() else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["--help"]
        p.environment = environment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }()
    static var supportsEffort: Bool { helpText.contains("--effort") }
    static var supportsSystemPrompt: Bool { helpText.contains("--system-prompt") }

    /// 子行程的工作目錄：一個空的中性資料夾
    static func neutralCwd() -> URL {
        let dir = SharedPaths.support.appendingPathComponent("claude-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static let isolationArgs: [String] = [
        "--tools", "",
        "--no-session-persistence",
        "--strict-mcp-config",
        "--setting-sources", "",
        "--disable-slash-commands",
        "--max-turns", "1",
    ]

    private static func cleanEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("CLAUDE") && !$0.key.hasPrefix("ANTHROPIC")
        }
    }
    /// 子行程環境：剝掉 CLAUDE*／ANTHROPIC*；只有使用者明寫 claudeConfigDir 才帶 CLAUDE_CONFIG_DIR（登入流程測試用）
    static func environment() -> [String: String] {
        var env = cleanEnvironment()
        if let d = UserDefaults.standard.string(forKey: "claudeConfigDir"), !d.isEmpty {
            env["CLAUDE_CONFIG_DIR"] = (d as NSString).expandingTildeInPath
        }
        return env
    }

    // ── 冷卻（失敗一次就先別再打，退本機）──────────────────────
    private static let cooldownLock = NSLock()
    private static var cooldownUntil: Date?
    private static var cooldownSecs: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "claudeCooldown")
        return v > 0 ? v : 600
    }
    /// 目前在冷卻期（給狀態顯示用）
    static var coolingDown: Bool {
        cooldownLock.lock()
        defer { cooldownLock.unlock() }
        if let u = cooldownUntil, u > Date() { return true }
        return false
    }
    static func resetCooldown() {
        cooldownLock.lock()
        cooldownUntil = nil
        cooldownLock.unlock()
    }

    static let loginHint = "本機 Claude Code 尚未登入或登入過期——在終端機跑一次 claude 登入後重試"
    private static func isAuthError(_ err: String?) -> Bool { err == loginHint }

    /// 最近一次「真的成功整理過一句」的時間。真實口述本身就是最好的探針——
    /// 有它就不需要另外花額度去試探。
    private static var lastGoodAt: Date?
    private static var recentlyGood: Bool {
        cooldownLock.lock()
        defer { cooldownLock.unlock() }
        guard let t = lastGoodAt else { return false }
        return Date().timeIntervalSince(t) < 600
    }

    // ── 背景探針 ─────────────────────────────────────────────
    // 過期憑證的 -p 要等滿逾時才失敗。引擎就緒後先在背景用一句小文字打一次：
    // 死的就先進冷卻＋排下一次探針；使用者的口述永遠不用替「沒登入」等 45 秒。
    // 順帶把常駐會話暖起來，第一句口述直接是暖的。
    //
    // ⚠ 省額度：這支原本掛在 startAll() 上，而 startAll()
    // 每次按下口述鍵都會跑一次——實測 67 次呼叫裡 38 次是探針，佔掉 48% 的輸入 token，
    // 每次只換回 2 個字，而且每次佔掉常駐會話一個 turn（40 turn 上限提早一半到、冷啟次數變兩倍）。
    // 現在兩道閘：①最近 10 分鐘成功整理過就不用探（真實口述已經證明活著）
    // ②沒登入直接跳過（loggedInNow 只要 0.13 秒、不花額度，比探針精準）。
    // 保護「憑證過期」的其實一直是啟動時那一次探針，不是每次口述那一次。
    //
    // ⚠ QoS 一定要 .userInitiated，不可以用 .utility（實測）：
    // 子行程會繼承「spawn 它的那條執行緒」的 QoS，而 Apple Silicon 上 .utility 會被排到
    // 節能核心並節流。同一句探針：.utility 93.3 秒、.userInitiated 2.5 秒——40 倍。
    // 而且探針起的是**常駐會話**，那顆 QoS 會跟著會話一輩子，之後每一句口述都慢。
    private static var probing = false
    private static var reprobeScheduled = false

    /// 探針自己的逾時，比口述的 45 秒短很多。理由是它會握著 warmLock：探針卡多久，
    /// 同時按下的那句口述就要在鎖上乾等多久（病史：就是這樣吃掉 90 秒中的前 45 秒）。
    /// 探針只是問一句「好」，正常 3–5 秒回；超過 12 秒本來就該判定它不健康、直接退本機。
    private static var probeTimeout: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "claudeProbeTimeout")
        return v > 0 ? v : 12
    }

    static func probeInBackground(reason: String) {
        guard available, PolishMode.current == .claudeCLI else { return }
        // 最近成功整理過＝已經知道它活著，不用再花一次額度確認
        if recentlyGood, reason == "engines-ready" {
            return
        }
        // 沒登入就別打了：打了也是等滿逾時才失敗，白花 45 秒
        if !loggedInNow {
            lastProbe = false
            TalkyLog.write("claude probe(\(reason)) 跳過：這台的 claude 沒登入")
            return
        }
        cooldownLock.lock()
        let busy = probing || (cooldownUntil.map { $0 > Date() } ?? false)
        if !busy { probing = true }
        cooldownLock.unlock()
        if busy { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let (out, err) = complete(
                system: TalkyServers.shared.claudeSystemPrompt(),
                user: TalkyServers.askPrefix + "好",
                timeoutOverride: probeTimeout)
            TalkyLog.write(
                "claude probe(\(reason)) \(out == nil ? "fail: " + (err ?? "?") : "ok")")
            lastProbe = (out != nil)
            cooldownLock.lock()
            probing = false
            cooldownLock.unlock()
        }
    }

    private static func scheduleReprobe() {
        cooldownLock.lock()
        let already = reprobeScheduled
        reprobeScheduled = true
        cooldownLock.unlock()
        if already { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + cooldownSecs + 1) {
            cooldownLock.lock()
            reprobeScheduled = false
            cooldownLock.unlock()
            probeInBackground(reason: "cooldown-expired")
        }
    }

    /// 口述潤飾入口。system 走 --system-prompt 整個取代（CLI 預設的長篇 agent 提示詞
    /// 不進口述潤飾：省 prefill、也不讓它把整理器當對話助理）。
    /// 走常駐會話（WarmSession）：冷啟 -p 的 1.5–2 秒 node 啟動只付一次；會話死了才退回冷啟。
    static func complete(system: String, user: String, timeoutOverride: TimeInterval? = nil) -> (
        String?, String?
    ) {
        // 沒登入就不要送出去等 45 秒逾時。0.13 秒問清楚，這句直接走本機，
        // 呼叫端會拿 loginHint 去面板上顯示「重新登入」那顆鈕。
        if !loggedInNow {
            lastProbe = false
            return (nil, loginHint)
        }
        cooldownLock.lock()
        if let u = cooldownUntil, u > Date() {
            let left = Int(u.timeIntervalSinceNow)
            cooldownLock.unlock()
            return (nil, "Claude Code 冷卻中（剩 \(left) 秒）——前一次失敗，先走本機")
        }
        cooldownLock.unlock()
        let d = UserDefaults.standard
        let t = d.double(forKey: "claudeTimeout")
        let model = Self.model
        let effort = d.string(forKey: "claudeEffort") ?? "low"
        let timeout = timeoutOverride ?? (t > 0 ? t : 45)
        var (out, err): (String?, String?)
        if supportsSystemPrompt, !d.bool(forKey: "claudeNoWarm") {
            (out, err) = warmComplete(
                system: system, user: user, model: model, effort: effort, timeoutSecs: timeout)
        } else {
            (out, err) = run(
                system: system, user: user, model: model, effort: effort,
                replaceSystemPrompt: supportsSystemPrompt, timeoutSecs: timeout)
        }
        cooldownLock.lock()
        if out == nil {
            cooldownUntil = Date().addingTimeInterval(cooldownSecs)
        } else {
            lastGoodAt = Date()  // 這句成功了＝下次不用再花額度探針
        }
        cooldownLock.unlock()
        lastProbe = (out != nil)
        if out == nil {
            TalkyLog.write("claude cooldown \(Int(cooldownSecs))s: \(err ?? "?")")
            scheduleReprobe()
        }
        return (out, err)
    }

    // ── 常駐會話 ─────────────────────────────────────────────
    // 冷啟 `claude -p` 每句要付 1.5–2 秒 node 啟動。改成一條
    // `--input-format stream-json --output-format stream-json` 雙向會話常駐：spawn 一次、
    // 每句口述當一則 user 訊息寫進 stdin、讀到 result 事件即回。實測同句冷 5s → 暖 2.4–2.9s。
    // 回收規則：每 warmMaxTurns 句重生（同一會話 context 會累積）、system prompt（含常用詞）／
    // 模型／effort 變了重生、任何錯誤／逾時／EOF 立刻殺掉（下一句自動重生）。app 退出時 shutdownWarm()。
    private static var warm: WarmSession?
    private static let warmLock = NSLock()  // 一次一句：口述本來就是序列的
    private static var warmMaxTurns: Int {
        let v = UserDefaults.standard.integer(forKey: "claudeWarmTurns")
        return v > 0 ? v : 40
    }

    private static func warmComplete(
        system: String, user: String, model: String, effort: String, timeoutSecs: TimeInterval
    ) -> (String?, String?) {
        warmLock.lock()
        defer { warmLock.unlock() }
        // 病史（當機）：complete() 的冷卻檢查在拿這把鎖「之前」，
        // 而 warmLock 一握就是整整一次 turn（最長 timeoutSecs）。9/11 15:30 實際發生的事——
        // 按下口述鍵同時觸發背景探針與這句口述，探針先搶到鎖卡滿 45 秒（並在失敗時設了
        // 600 秒冷卻），這句在鎖上排隊 45 秒，拿到鎖後不重查冷卻、又自己卡滿 45 秒。
        // 使用者面前是 90 秒一動不動。這裡補一次重查：前面那句已經判定壞掉就直接退本機。
        cooldownLock.lock()
        let cd = cooldownUntil
        cooldownLock.unlock()
        if let u = cd, u > Date() {
            return (nil, "Claude Code 冷卻中（剩 \(Int(u.timeIntervalSinceNow)) 秒）——前一次失敗，先走本機")
        }
        if let w = warm,
            !w.alive || w.systemPrompt != system || w.model != model || w.effort != effort
                || w.turns >= warmMaxTurns
        {
            TalkyLog.write(
                "claude warm recycle turns=\(w.turns) alive=\(w.alive) reason=\(!w.alive ? "dead" : w.turns >= warmMaxTurns ? "maxTurns" : "config")"
            )
            w.kill()
            warm = nil
        }
        if warm == nil {
            guard let bin = binaryPath() else {
                return (nil, "找不到本機 claude（安裝 Claude Code，或設定 claudePath）")
            }
            let t0 = Date()
            guard
                let w = WarmSession(
                    bin: bin, system: system, model: model, effort: supportsEffort ? effort : nil,
                    extraArgs: UserDefaults.standard.string(forKey: "claudeExtraArgs"),
                    env: environment())
            else { return (nil, "claude 啟動失敗（常駐會話）") }
            warm = w
            TalkyLog.write(
                String(
                    format: "claude warm spawn model=%@ %.1fs", model, Date().timeIntervalSince(t0)))
        }
        let w = warm!
        TalkyLog.write(
            "polish claude start model=\(model) chars=\(system.count + user.count) turn=\(w.turns + 1)")
        let t0 = Date()
        let (out, err) = w.turn(user: user, timeoutSecs: timeoutSecs)
        w.turns += 1
        TalkyLog.write(
            String(
                format: "polish claude done %.1fs turn=%d out=%d chars%@",
                Date().timeIntervalSince(t0), w.turns, out?.count ?? 0, err.map { " err=" + $0 } ?? ""
            ))
        if out == nil {
            w.kill()
            warm = nil
        }
        return (out, err)
    }

    /// app 退出時收掉常駐會話（不收＝孤兒 node 進程）
    static func shutdownWarm() {
        warmLock.lock()
        warm?.kill()
        warm = nil
        warmLock.unlock()
    }

    /// 錯誤文字分類：登入類一律轉成 loginHint（冷卻／快失敗邏輯認這句）
    private static func classify(_ text: String) -> String {
        let hint = text.lowercased()
        if hint.contains("login") || hint.contains("authenticate") || hint.contains("not logged in")
            || hint.contains("api key") || hint.contains("token has expired")
        {
            return loginHint
        }
        return text
    }

    final class WarmSession {
        let systemPrompt: String
        let model: String
        let effort: String
        var turns = 0
        private let process = Process()
        private let inPipe = Pipe()
        private let outPipe = Pipe()
        private let errPipe = Pipe()
        private let cond = NSCondition()
        private var buffer = Data()
        private var lines: [String] = []
        private var eof = false
        private var errTail = ""
        private var seenLines = 0  // 收到幾行 stream-json（逾時診斷用）

        var alive: Bool {
            cond.lock()
            defer { cond.unlock() }
            return process.isRunning && !eof
        }

        init?(
            bin: String, system: String, model: String, effort: String?, extraArgs: String?,
            env: [String: String]
        ) {
            systemPrompt = system
            self.model = model
            self.effort = effort ?? ""
            var args =
                [
                    "-p", "--model", model,
                    "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                ] + ClaudeCLI.isolationArgs + ["--system-prompt", system]
            if let e = effort { args += ["--effort", e] }
            if let extra = extraArgs, !extra.isEmpty {
                args += extra.split(separator: " ").map(String.init)
            }
            process.executableURL = URL(fileURLWithPath: bin)
            process.arguments = args
            process.environment = env
            process.currentDirectoryURL = ClaudeCLI.neutralCwd()
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = errPipe
            do { try process.run() } catch { return nil }
            outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                guard let self else { return }
                let d = h.availableData
                self.cond.lock()
                if d.isEmpty {
                    self.eof = true
                    h.readabilityHandler = nil
                } else {
                    self.buffer.append(d)
                    while let nl = self.buffer.firstIndex(of: 0x0A) {
                        let lineData = self.buffer.subdata(in: 0..<nl)
                        self.buffer.removeSubrange(0...nl)
                        if let s = String(data: lineData, encoding: .utf8), !s.isEmpty {
                            self.lines.append(s)
                            self.seenLines += 1
                        }
                    }
                }
                self.cond.broadcast()
                self.cond.unlock()
            }
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                guard let self else { return }
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    return
                }
                self.cond.lock()
                self.errTail = String(
                    (self.errTail + (String(data: d, encoding: .utf8) ?? "")).suffix(400))
                self.cond.unlock()
            }
        }

        /// 送一句、等 result 事件。逾時／EOF 都回錯（呼叫端會殺掉會話）
        func turn(user: String, timeoutSecs: TimeInterval) -> (String?, String?) {
            let msg: [String: Any] = [
                "type": "user",
                "message": ["role": "user", "content": [["type": "text", "text": user]]],
            ]
            guard var data = try? JSONSerialization.data(withJSONObject: msg) else {
                return (nil, "request 組裝失敗")
            }
            data.append(0x0A)
            DispatchQueue.global(qos: .userInitiated).async { [inPipe] in
                inPipe.fileHandleForWriting.write(data)
            }
            let deadline = Date().addingTimeInterval(timeoutSecs)
            cond.lock()
            defer { cond.unlock() }
            while true {
                while !lines.isEmpty {
                    let line = lines.removeFirst()
                    guard
                        let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                            as? [String: Any],
                        obj["type"] as? String == "result"
                    else { continue }
                    let text = ((obj["result"] as? String) ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    if obj["is_error"] as? Bool == true || text.isEmpty {
                        let tail = errTail.split(separator: "\n").suffix(2).joined(separator: " ")
                        return (
                            nil,
                            ClaudeCLI.classify(
                                "Claude Code 潤飾失敗："
                                    + (text.isEmpty ? tail : String(text.prefix(200))))
                        )
                    }
                    return (text, nil)
                }
                if eof {
                    let tail = errTail.split(separator: "\n").suffix(2).joined(separator: " ")
                    return (
                        nil,
                        ClaudeCLI.classify("claude 會話結束" + (tail.isEmpty ? "" : "：" + tail))
                    )
                }
                if Date() >= deadline {
                    // 逾時要把子行程講過的話帶出來，否則「卡住」永遠只是一句沒有線索的逾時。
                    // seen＝收到幾行 stream-json（0＝CLI 連 init 事件都沒吐，問題在啟動不在生成）
                    let tail = errTail.split(separator: "\n").suffix(2).joined(separator: " ")
                    return (
                        nil,
                        "Claude Code 潤飾逾時（\(Int(timeoutSecs)) 秒，seen=\(seenLines)\(tail.isEmpty ? "" : "，" + tail)）——可重講，或改回本機模型"
                    )
                }
                _ = cond.wait(until: deadline)
            }
        }

        func kill() {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            try? inPipe.fileHandleForWriting.close()  // stdin EOF＝CLI 自己會退
            if process.isRunning { process.terminate() }
        }
    }

    /// 冷啟一次性呼叫（常駐會話不可用時的退路）
    private static func run(
        system: String, user: String, model: String, effort: String,
        replaceSystemPrompt: Bool, timeoutSecs: TimeInterval
    ) -> (String?, String?) {
        guard let bin = binaryPath() else {
            return (nil, "找不到本機 claude（安裝 Claude Code，或設定 claudePath）")
        }
        let d = UserDefaults.standard
        var args =
            ["-p", "--model", model, "--output-format", "text"] + isolationArgs + [
                replaceSystemPrompt ? "--system-prompt" : "--append-system-prompt", system,
            ]
        if supportsEffort { args += ["--effort", effort] }
        if let extra = d.string(forKey: "claudeExtraArgs"), !extra.isEmpty {
            args += extra.split(separator: " ").map(String.init)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.environment = environment()
        p.currentDirectoryURL = neutralCwd()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch {
            return (nil, "claude 啟動失敗：\(error.localizedDescription)")
        }
        TalkyLog.write("polish claude(cold) start model=\(model) chars=\(system.count + user.count)")
        let t0 = Date()
        // 寫 stdin 要在背景（大逐字稿塞爆 pipe buffer 會互等死鎖）
        DispatchQueue.global(qos: .userInitiated).async {
            inPipe.fileHandleForWriting.write(user.data(using: .utf8) ?? Data())
            try? inPipe.fileHandleForWriting.close()
        }
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeoutSecs) == .timedOut {
            p.terminate()
            TalkyLog.write("polish claude(cold) timeout \(Int(timeoutSecs))s")
            return (nil, "Claude Code 潤飾逾時（\(Int(timeoutSecs)) 秒）——可重講，或改回本機模型")
        }
        p.waitUntilExit()
        let out =
            String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""
        TalkyLog.write(
            String(
                format: "polish claude(cold) done %.0fs exit=%d out=%d chars",
                Date().timeIntervalSince(t0), p.terminationStatus, out.count))
        guard p.terminationStatus == 0, !out.isEmpty else {
            let tail = errText.split(separator: "\n").suffix(2).joined(separator: " ")
            let msg = "Claude Code 潤飾失敗（exit \(p.terminationStatus)）\(tail.isEmpty ? "" : "：" + tail)"
            let classified = classify(errText + out)
            return (nil, classified == loginHint ? loginHint : msg)
        }
        return (out, nil)
    }
}
