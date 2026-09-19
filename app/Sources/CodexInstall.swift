// CodexInstall — 在 app 裡直接裝 Codex（OpenAI 官方 GitHub release 的獨立執行檔，不需 Node、不需 ChatGPT 桌面版、不開終端機）
//
// 0.1.3 build 11：只用 ChatGPT／Codex 的人走同一條路——按下去就跳出登入頁，登入完馬上綁定
// 流程跟 Claude 那條一樣：下載（URLSession，有進度）→ 解壓到 ~/Library/Application Support/Talky/bin/codex → --version 驗證
// → 裝好直接接 CodexLogin（瀏覽器登入）→ 登入成功 Brains.select(.codex) 綁定。
// defaults `codexInstallURL` 可覆寫（測試或鏡像）。

import AppKit
import Foundation

final class CodexInstall: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = CodexInstall()

    static var releaseURL: URL {
        let s = UserDefaults.standard.string(forKey: "codexInstallURL")
            ?? "https://github.com/openai/codex/releases/latest/download/codex-aarch64-apple-darwin.tar.gz"
        return URL(string: s) ?? URL(string: "https://github.com/openai/codex/releases/latest")!
    }
    static var installDir: URL { SharedPaths.support.appendingPathComponent("bin", isDirectory: true) }
    static var installedPath: String { installDir.appendingPathComponent("codex").path }

    @Published var running = false
    @Published var failed = false
    @Published var succeeded = false
    @Published var fraction: Double = 0
    @Published var note = ""

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var startedAt = Date()

    @discardableResult
    func start() -> Bool {
        if running { return true }
        running = true
        failed = false
        succeeded = false
        fraction = 0
        startedAt = Date()
        note = "正在下載 ChatGPT 的 Codex（約 90MB，看網路 1–3 分鐘）…"
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        let t = s.downloadTask(with: Self.releaseURL)
        task = t
        t.resume()
        TalkyLog.write("codex install start \(Self.releaseURL.absoluteString)")
        return true
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
        failed = false
        note = "已取消。"
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let f = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.fraction = f
            self.note = String(format: "下載中 %.0f%%", f * 100)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 這個回呼結束後暫存檔會被系統清掉：同步搬走、解壓、驗證
        let fm = FileManager.default
        let dir = Self.installDir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let tgz = dir.appendingPathComponent("codex.tar.gz")
        do {
            if fm.fileExists(atPath: tgz.path) {
                _ = try fm.replaceItemAt(tgz, withItemAt: location)
            } else {
                try fm.moveItem(at: location, to: tgz)
            }
        } catch {
            finish(false, "存檔失敗：\(error.localizedDescription)")
            return
        }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tgz.path, "-C", dir.path]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        do {
            try tar.run()
            tar.waitUntilExit()
        } catch {
            finish(false, "解壓失敗：\(error.localizedDescription)")
            return
        }
        // 壓縮檔裡是單一執行檔，名稱可能是 codex 或 codex-aarch64-apple-darwin
        let items = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let extracted = items.first { $0.hasPrefix("codex-") && !$0.hasSuffix(".gz") }
        let final = dir.appendingPathComponent("codex")
        if let name = extracted {
            let src = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: final.path) {
                _ = try? fm.replaceItemAt(final, withItemAt: src)
            } else {
                try? fm.moveItem(at: src, to: final)
            }
        }
        guard fm.fileExists(atPath: final.path) else {
            finish(false, "壓縮檔裡找不到 codex（tar exit \(tar.terminationStatus)）")
            return
        }
        chmod(final.path, 0o755)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "com.apple.quarantine", final.path]
        xattr.standardOutput = FileHandle.nullDevice
        xattr.standardError = FileHandle.nullDevice
        try? xattr.run()
        xattr.waitUntilExit()
        // 真的跑得起來？
        let v = Process()
        v.executableURL = final
        v.arguments = ["--version"]
        let out = Pipe()
        v.standardOutput = out
        v.standardError = out
        var ver = ""
        do {
            try v.run()
            ver = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            v.waitUntilExit()
        } catch {
            finish(false, "codex 跑不起來：\(error.localizedDescription)")
            return
        }
        guard v.terminationStatus == 0 else {
            finish(false, "codex 跑不起來（exit \(v.terminationStatus)）")
            return
        }
        finish(true, "Codex 裝好了（\(ver)，\(Int(Date().timeIntervalSince(startedAt))) 秒）。接著登入你的 ChatGPT：")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error as NSError?, e.code != NSURLErrorCancelled {
            finish(false, "下載失敗：\(e.localizedDescription)")
        }
    }

    private func finish(_ ok: Bool, _ msg: String) {
        DispatchQueue.main.async {
            self.running = false
            self.succeeded = ok
            self.failed = !ok
            self.note = msg
            self.task = nil
            TalkyLog.write("codex install \(ok ? "ok" : "fail"): \(msg)")
            if ok {
                CodexCLI.resetLoginCache()
                CodexLogin.shared.start()  // 裝好直接接登入（少按一次）
            }
        }
    }
}
