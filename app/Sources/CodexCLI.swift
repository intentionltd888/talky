// CodexCLI — 用使用者自己的 ChatGPT 訂閱額度整理（OpenAI Codex CLI，`codex exec`）
//
// 原則：一律先用使用者自己訂閱方案的額度（桌面版背後那份），
// 不打 API；API 金鑰只是選項。
//
// 找 codex 的順序：①ChatGPT 桌面版自帶的那顆（/Applications/ChatGPT.app/Contents/Resources/codex，
// 裝了桌面版、登入過就能用，什麼都不用另裝）②另外裝的 codex 指令（npm／brew）。
// 登入狀態＝`codex login status`（ChatGPT 帳號，吃 Plus／Pro 額度）。永遠不帶 OPENAI_API_KEY 進子行程，
// 免得它改走 API 計費。
// 跑法＝`codex exec` 非互動＋唯讀沙箱＋中性空資料夾＋不讀使用者設定與規則檔，最後一則訊息寫到暫存檔再讀回
// （stdout 會混進 banner）。實測（ChatGPT.app 內建 0.153.4）：一句 7–8 秒。

import AppKit
import Foundation

enum CodexCLI {
    static var available: Bool { binaryPath() != nil }
    static let loginHint = "Codex 還沒登入 ChatGPT——按「登入」跟著終端機做一次"

    /// 最近一次探針／口述的結果（nil＝還沒試過）
    static var lastProbe: Bool? {
        get { UserDefaults.standard.object(forKey: "codexLastProbeOK") as? Bool }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "codexLastProbeOK") } else {
                UserDefaults.standard.removeObject(forKey: "codexLastProbeOK")
            }
        }
    }

    static func binaryPath() -> String? {
        var candidates: [String] = []
        if let p = UserDefaults.standard.string(forKey: "codexPath"), !p.isEmpty {
            candidates.append((p as NSString).expandingTildeInPath)
        }
        let home = NSHomeDirectory()
        candidates += [
            CodexInstall.installedPath,  // app 自己下載的獨立執行檔（0.1.3 build 11）
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            home + "/Applications/ChatGPT.app/Contents/Resources/codex",
            home + "/.npm-global/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home + "/.local/bin/codex",
            home + "/.bun/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    /// 用的是 ChatGPT 桌面版自帶的那顆
    static var viaChatGPTApp: Bool { binaryPath()?.contains("ChatGPT.app") == true }
    static var chatGPTAppInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app") }

    /// 登入了沒（`codex login status`，約 0.3 秒；連接面每 3 秒問一次所以快取 20 秒）
    private static var loginCache: (Date, Bool)?
    private static let loginLock = NSLock()
    static func loggedIn(force: Bool = false) -> Bool? {
        guard let bin = binaryPath() else { return nil }
        loginLock.lock()
        if !force, let (t, v) = loginCache, Date().timeIntervalSince(t) < 20 {
            loginLock.unlock()
            return v
        }
        loginLock.unlock()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["login", "status"]
        p.environment = cleanEnvironment()
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        let ok = p.terminationStatus == 0 && text.lowercased().contains("logged in")
        loginLock.lock()
        loginCache = (Date(), ok)
        loginLock.unlock()
        return ok
    }
    static func resetLoginCache() {
        loginLock.lock()
        loginCache = nil
        loginLock.unlock()
    }

    /// 子行程環境：拿掉任何 OPENAI／CODEX 變數（有 OPENAI_API_KEY 它會改走 API 計費，違反「用訂閱額度」）
    /// 給 CodexLogin 用（跟 polish 一樣剝掉金鑰）
    static func environment() -> [String: String] { cleanEnvironment() }

    private static func cleanEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("OPENAI") && !$0.key.hasPrefix("CODEX")
        }
    }

    /// 中性工作目錄（空資料夾；唯讀沙箱也只看得到這裡）
    static func neutralCwd() -> URL {
        let u = SharedPaths.support.appendingPathComponent("codex-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// 整理一句。system＝規則本體、user＝askPrefix＋逐字稿；少樣本直接排進提示（codex exec 沒有 system 槽）。
    static func complete(system: String, user: String) -> (String?, String?) {
        guard let bin = binaryPath() else {
            return (nil, "找不到 codex（裝 ChatGPT 桌面版就有；或 npm install -g @openai/codex）")
        }
        var prompt = system
        prompt += "\n每則訊息各自獨立：只整理這一則的內容。不要使用任何工具、不要讀寫檔案、不要問問題，直接回覆整理後的文字。"
        prompt += "\n\n整理範例（輸入 → 輸出）：\n"
        for (u, a) in TalkyServers.fewshot {
            prompt += "輸入：\(u.replacingOccurrences(of: TalkyServers.askPrefix, with: ""))\n輸出：\(a)\n\n"
        }
        prompt += user
        let d = UserDefaults.standard
        let t = d.double(forKey: "codexTimeout")
        let timeout = t > 0 ? t : 60
        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("talky-codex-\(UUID().uuidString).txt")
        var args = [
            "exec", "-s", "read-only", "-C", neutralCwd().path, "--skip-git-repo-check", "--ephemeral",
            "--ignore-user-config", "--ignore-rules", "--color", "never", "-o", outFile.path,
        ]
        if let m = d.string(forKey: "codexModel"), !m.isEmpty { args += ["-m", m] }
        args.append(prompt)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.environment = cleanEnvironment()
        p.currentDirectoryURL = neutralCwd()
        p.standardInput = FileHandle.nullDevice  // 不給 stdin，它才不會等「additional input」
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch {
            return (nil, "codex 啟動失敗：\(error.localizedDescription)")
        }
        TalkyLog.write("polish codex start via=\(viaChatGPTApp ? "ChatGPT.app" : "cli") chars=\(prompt.count)")
        let t0 = Date()
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
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            TalkyLog.write("polish codex timeout \(Int(timeout))s")
            lastProbe = false
            return (nil, "Codex 潤飾逾時（\(Int(timeout)) 秒）——可重講，或改回本機模型")
        }
        p.waitUntilExit()
        let last = (try? String(contentsOf: outFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? FileManager.default.removeItem(at: outFile)
        let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""
        let out = last.isEmpty ? stdout : last
        TalkyLog.write(
            String(
                format: "polish codex done %.1fs exit=%d out=%d chars", Date().timeIntervalSince(t0),
                p.terminationStatus, out.count))
        guard p.terminationStatus == 0, !out.isEmpty else {
            let low = (errText + stdout).lowercased()
            lastProbe = false
            if low.contains("not logged in") || low.contains("login") && low.contains("required") || low.contains("401")
                || low.contains("unauthorized")
            {
                resetLoginCache()
                return (nil, loginHint)
            }
            let tail = errText.split(separator: "\n").suffix(2).joined(separator: " ")
            return (nil, "Codex 潤飾失敗（exit \(p.terminationStatus)）\(tail.isEmpty ? "" : "：" + tail)")
        }
        lastProbe = true
        return (out, nil)
    }
}
