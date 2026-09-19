// ClaudeLogin — 在 app 裡直接完成 Claude Code 登入（不開終端機、不要「自動化」權限）
//
// 病史：使用者的 Claude 桌面版登入了，但 `~/.local/bin/claude` 這顆命令列從沒登入過
// （桌面版用自己的鑰匙圈項目，兩邊不共用），只能請他「去終端機跑一次 claude」——多數人不會做，整條線就斷在這。
// 所以登入要在 app 裡一路做完。
//
// 實測（CLI 2.1.263）`claude auth login` 不需要 TTY：stdout 印
//   Opening browser to sign in…
//   If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?…
//   Paste code here if prompted >
// 所以 Talky 自己 spawn 它：CLI 會開瀏覽器；沒開就給他 URL；網頁最後若給一串代碼，貼進 Talky 的格子寫回 stdin；
// 同時每 2 秒問 `claude auth status`，loggedIn 一變 true 就算完成（localhost 回呼那條路不用貼代碼）。

import AppKit
import Foundation

final class ClaudeLogin: ObservableObject {
    static let shared = ClaudeLogin()

    @Published var running = false
    @Published var needsCode = false
    @Published var url: String?
    @Published var note = ""
    @Published var succeeded = false

    private var process: Process?
    private var inPipe: Pipe?
    private var outBuffer = ""
    private var poll: Timer?
    private var startedAt = Date()

    /// 開始登入。回傳 false＝連 claude 都起不來（呼叫端退成終端機）
    @discardableResult
    func start() -> Bool {
        if running { return true }
        guard let bin = ClaudeCLI.binaryPath() else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["auth", "login"]
        var env = ClaudeCLI.environment()
        env.removeValue(forKey: "BROWSER")  // 讓它用系統預設瀏覽器
        p.environment = env
        p.currentDirectoryURL = ClaudeCLI.neutralCwd()
        let inP = Pipe()
        let outP = Pipe()
        p.standardInput = inP
        p.standardOutput = outP
        p.standardError = outP
        outP.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consume(s) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.processEnded(status: proc.terminationStatus) }
        }
        do { try p.run() } catch {
            TalkyLog.write("claude login spawn fail: \(error.localizedDescription)")
            return false
        }
        process = p
        inPipe = inP
        outBuffer = ""
        url = nil
        needsCode = false
        succeeded = false
        running = true
        startedAt = Date()
        note = "瀏覽器會打開 Claude 的登入頁：用你的 Claude 帳號登入並按「允許」。"
        TalkyLog.write("claude login start")
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkStatus() }
        return true
    }

    private func consume(_ s: String) {
        outBuffer += s
        if url == nil, let r = outBuffer.range(of: "https://") {
            let tail = outBuffer[r.lowerBound...]
            let end = tail.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\r" }) ?? tail.endIndex
            url = String(tail[..<end])
        }
        if outBuffer.contains("Paste code"), !needsCode {
            needsCode = true
            note = "登入後網頁會給你一串代碼：複製它，貼到下面那格按「送出」。（有些情況登入完會自動接上，不用貼）"
        }
        let low = outBuffer.lowercased()
        if low.contains("error") || low.contains("failed") {
            let line = outBuffer.split(separator: "\n").last(where: { $0.lowercased().contains("error") || $0.lowercased().contains("fail") })
            if let l = line { note = "登入沒成功：\(String(l).prefix(160))。可以再按一次「登入」。" }
        }
    }

    /// 把瀏覽器給的代碼寫回 CLI
    func submit(code: String) {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, let h = inPipe?.fileHandleForWriting else { return }
        h.write(Data((c + "\n").utf8))
        note = "代碼已送出，確認中…"
        TalkyLog.write("claude login code submitted (\(c.count) chars)")
    }

    func openBrowserAgain() {
        if let u = url, let x = URL(string: u) { NSWorkspace.shared.open(x) }
    }

    private func checkStatus() {
        guard running else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let st = ClaudeCLI.authStatus(force: true)
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if st?.loggedIn == true { self.finish(ok: true) } else if Date().timeIntervalSince(self.startedAt) > 600 {
                    self.note = "等了 10 分鐘還沒登入，先取消；要再試就再按一次「登入」。"
                    self.finish(ok: false)
                }
            }
        }
    }

    private func processEnded(status: Int32) {
        guard running else { return }
        TalkyLog.write("claude login process exit=\(status)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let st = ClaudeCLI.authStatus(force: true)
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if st?.loggedIn == true {
                    self.finish(ok: true)
                } else {
                    self.note = status == 0
                        ? "CLI 說完成了，但還沒看到登入狀態；再按一次「測試」看看。"
                        : "登入沒完成（exit \(status)）。再按一次「登入」，或改用終端機。"
                    self.finish(ok: false)
                }
            }
        }
    }

    private func finish(ok: Bool) {
        poll?.invalidate()
        poll = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        try? inPipe?.fileHandleForWriting.close()
        inPipe = nil
        running = false
        needsCode = false
        succeeded = ok
        if ok {
            note = "登入成功，已接上你的 Claude。"
            TalkyLog.write("claude login ok")
            ClaudeCLI.resetCooldown()
            ClaudeCLI.lastProbe = nil
            ClaudeCLI.probeInBackground(reason: "login-ok")
        }
    }

    func cancel() {
        note = "已取消。"
        finish(ok: false)
    }
}
