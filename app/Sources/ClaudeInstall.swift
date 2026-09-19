// ClaudeInstall — 在 app 裡直接裝 Claude Code（官方原生安裝腳本；不需 Node、不需 sudo、不開終端機、不要任何權限）
//
// 0.1.2：以前「安裝」是打開終端機貼指令——阿嬤看到終端機就停了。
// 官方腳本 `curl -fsSL https://claude.ai/install.sh | bash` 只寫 $HOME（~/.local/bin/claude），明文拒絕 sudo，
// 所以 Talky 自己 spawn /bin/bash 跑它就好；stdout 最後一行當進度，exit 0 而且找得到 claude ＝裝好。
// 裝好直接接 ClaudeLogin（少按一次「登入」）。退路：spawn 起不來 → Brains.perform 退回終端機／複製指令。

import AppKit
import Foundation

final class ClaudeInstall: ObservableObject {
    static let shared = ClaudeInstall()

    @Published var running = false
    @Published var failed = false
    @Published var succeeded = false
    @Published var note = ""

    private var process: Process?
    private var outPipe: Pipe?
    private var buffer = ""
    private var startedAt = Date()

    /// 回傳 false＝連 bash 都起不來（呼叫端退成終端機）
    @discardableResult
    func start() -> Bool {
        if running { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", Brains.claudeInstallCommand]
        var env = ClaudeCLI.environment()
        env["HOME"] = NSHomeDirectory()
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        p.environment = env
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
            DispatchQueue.main.async { self?.ended(status: proc.terminationStatus) }
        }
        do { try p.run() } catch {
            TalkyLog.write("claude install spawn fail: \(error.localizedDescription)")
            return false
        }
        process = p
        outPipe = out
        buffer = ""
        running = true
        failed = false
        succeeded = false
        startedAt = Date()
        note = "正在下載並安裝 Claude Code（通常 1 分鐘內，看網路）…"
        TalkyLog.write("claude install start")
        return true
    }

    private func consume(_ s: String) {
        buffer += s
        // 最後一行非空白當進度；curl 的百分比行太吵，略過
        let lines = buffer.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if let last = lines.last(where: { !$0.isEmpty && !$0.contains("%") && !$0.hasPrefix("#") }) {
            note = "安裝中：" + String(last.prefix(90))
        }
    }

    private func ended(status: Int32) {
        outPipe?.fileHandleForReading.readabilityHandler = nil
        outPipe = nil
        process = nil
        running = false
        ClaudeCLI.resetAuthCache()
        ClaudeCLI.resetCooldown()
        let bin = ClaudeCLI.binaryPath()
        let ok = status == 0 && bin != nil
        succeeded = ok
        failed = !ok
        let secs = Int(Date().timeIntervalSince(startedAt))
        if ok {
            note = "Claude Code 裝好了（\(secs) 秒）。接著登入你的 Claude："
            TalkyLog.write("claude install ok \(secs)s → \(bin ?? "?")")
            // 裝好直接接登入：瀏覽器會打開，他按允許就完成
            ClaudeLogin.shared.start()
        } else {
            let tail = buffer.split(separator: "\n").suffix(3).map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " / ")
            note = "安裝沒成功（exit \(status)）：\(String(tail.prefix(200)))。再按一次「安裝」；還是不行就用「複製指令」貼到終端機。"
            TalkyLog.write("claude install fail exit=\(status): \(tail)")
        }
    }

    func cancel() {
        if let p = process, p.isRunning { p.terminate() }
        note = "已取消。"
        running = false
        failed = false
    }
}
