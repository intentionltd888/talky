// CodexLogin — 在 app 裡完成 ChatGPT（Codex）登入：spawn `codex login`（它自己開瀏覽器、起本機回呼），
// 每 2 秒問 `codex login status`，一變 Logged in 就 Brains.select(.codex) 綁定。跟 ClaudeLogin 同一套。

import AppKit
import Foundation

final class CodexLogin: ObservableObject {
    static let shared = CodexLogin()

    @Published var running = false
    @Published var url: String?
    @Published var note = ""
    @Published var succeeded = false

    private var process: Process?
    private var outPipe: Pipe?
    private var buffer = ""
    private var poll: Timer?
    private var startedAt = Date()

    /// 回傳 false＝這台沒有 codex（呼叫端先走 CodexInstall）
    @discardableResult
    func start() -> Bool {
        if running { return true }
        guard let bin = CodexCLI.binaryPath() else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["login"]
        p.environment = CodexCLI.environment()
        p.currentDirectoryURL = ClaudeCLI.neutralCwd()
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consume(s) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.ended(proc.terminationStatus) }
        }
        do { try p.run() } catch {
            TalkyLog.write("codex login spawn fail: \(error.localizedDescription)")
            return false
        }
        process = p
        outPipe = out
        buffer = ""
        url = nil
        succeeded = false
        running = true
        startedAt = Date()
        note = "瀏覽器會打開 ChatGPT 的登入頁：登入你的帳號、按「允許」，回來這裡會自動接上。"
        TalkyLog.write("codex login start")
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.check() }
        return true
    }

    private func consume(_ s: String) {
        buffer += s
        if url == nil, let r = buffer.range(of: "https://") {
            let tail = buffer[r.lowerBound...]
            let end = tail.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\r" }) ?? tail.endIndex
            url = String(tail[..<end])
        }
    }

    private func check() {
        guard running else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = CodexCLI.loggedIn(force: true) == true
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if ok {
                    self.finish(true)
                } else if Date().timeIntervalSince(self.startedAt) > 600 {
                    self.note = "等了 10 分鐘還沒登入，先取消；要再試就再按一次「登入」。"
                    self.finish(false)
                }
            }
        }
    }

    private func ended(_ status: Int32) {
        guard running else { return }
        TalkyLog.write("codex login process exit=\(status)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = CodexCLI.loggedIn(force: true) == true
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if ok {
                    self.finish(true)
                } else {
                    self.note = "登入沒完成（exit \(status)）。再按一次「登入」。"
                    self.finish(false)
                }
            }
        }
    }

    private func finish(_ ok: Bool) {
        poll?.invalidate()
        poll = nil
        outPipe?.fileHandleForReading.readabilityHandler = nil
        outPipe = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        running = false
        succeeded = ok
        if ok {
            note = "登入成功，已接上你的 ChatGPT。"
            TalkyLog.write("codex login ok → select codex")
            CodexCLI.resetLoginCache()
            Brains.select(.codex)  // 登入完馬上綁定
        }
    }

    func openBrowserAgain() {
        if let u = url, let x = URL(string: u) { NSWorkspace.shared.open(x) }
    }

    func cancel() {
        note = "已取消。"
        finish(false)
    }
}
