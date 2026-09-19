// Downloads — 模型來源表＋可續傳、會校驗的下載器
//
// 預設行為（自建／開源版）：**只連 HuggingFace**，SHA256 內建在程式裡。
// app 不會去問任何自家伺服器要 manifest，也不會回報任何東西。
//
// 兩個給進階使用者的設定鍵（預設都關，設了才生效）：
//   defaults write ltd.intention.talky modelMirrorBase -string "https://你的鏡像/"
//   defaults write ltd.intention.talky modelManifestEnabled -bool YES
// 前者＝在 HuggingFace 前面插一個自己的鏡像（企業內網、或官方封裝版的加速來源）；
// 後者＝允許從該鏡像抓 manifest.json 更新體積／SHA。兩個都沒設＝零對外請求（除了下載模型本身）。
//
// 下載器本體是實戰版：.part 落地＋HTTP Range 續傳（跨來源接力）、多輪輪替、停滯看門狗、
// 完成時 SHA256 全檔比對、下載前先查磁碟空間。

import CryptoKit
import Foundation

// MARK: - 來源表

enum ModelCatalog {
    struct Spec {
        let id: String
        var file: String
        var path: String  // 鏡像鍵（相對 base）
        var bytes: Int64
        var sha256: String?
        var fallback: URL?  // HuggingFace 原檔
    }

    /// 使用者自己設的鏡像（預設空＝不打任何自家伺服器）
    static var mirrorBase: String? {
        let v = UserDefaults.standard.string(forKey: "modelMirrorBase")
        return (v?.isEmpty == false) ? v : nil
    }
    /// manifest 更新（預設關）
    static var manifestEnabled: Bool { UserDefaults.standard.bool(forKey: "modelManifestEnabled") }

    /// 內建真值（2026-09 實測）：體積與 SHA256 都寫死在程式裡，不需要任何伺服器背書
    static var whisper = Spec(
        id: "whisper", file: "ggml-large-v3-turbo.bin", path: "models/ggml-large-v3-turbo.bin",
        bytes: 1_624_555_275,
        sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
        fallback: URL(
            string:
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")
    )
    static var qwen = Spec(
        id: "qwen", file: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
        path: "models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
        bytes: 2_497_281_120,
        sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597",
        fallback: URL(
            string:
                "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
        )
    )

    /// 下載來源順序：使用者設的鏡像（如果有）→ HuggingFace
    static func downloadSources(_ s: Spec) -> [URL] {
        var out: [URL] = []
        if let b = mirrorBase {
            let base = b.hasSuffix("/") ? b : b + "/"
            if let u = URL(string: base + s.path) { out.append(u) }
        }
        if let f = s.fallback { out.append(f) }
        return out
    }

    // ── manifest（預設關）──────────────────────────────────────
    private static var cacheURL: URL { SharedPaths.support.appendingPathComponent("manifest.json") }

    static func loadCached() {
        guard manifestEnabled, let d = try? Data(contentsOf: cacheURL) else { return }
        _ = apply(d)
    }

    static func refresh(completion: ((Bool) -> Void)? = nil) {
        guard manifestEnabled, let base = mirrorBase else {
            completion?(false)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let b = base.hasSuffix("/") ? base : base + "/"
            guard let u = URL(string: b + "manifest.json") else {
                completion?(false)
                return
            }
            var req = URLRequest(url: u, timeoutInterval: 12)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let sem = DispatchSemaphore(value: 0)
            var got: Data?
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let data, (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 50 {
                    got = data
                }
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 15)
            if let got, apply(got) {
                try? FileManager.default.createDirectory(
                    at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? got.write(to: cacheURL, options: .atomic)
                TalkyLog.write("manifest refreshed")
                completion?(true)
                return
            }
            TalkyLog.write("manifest refresh failed（用內建預設）")
            completion?(false)
        }
    }

    @discardableResult
    private static func apply(_ data: Data) -> Bool {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = j["models"] as? [String: Any]
        else { return false }
        func upd(_ s: inout Spec, _ m: [String: Any]?) {
            guard let m else { return }
            if let f = m["file"] as? String, !f.isEmpty { s.file = f }
            if let p = m["path"] as? String, !p.isEmpty { s.path = p }
            if let b = m["bytes"] as? NSNumber { s.bytes = b.int64Value }
            if let h = m["sha256"] as? String, h.count == 64 { s.sha256 = h.lowercased() }
            if let fb = m["fallback"] as? String, let u = URL(string: fb) { s.fallback = u }
        }
        upd(&whisper, models["whisper"] as? [String: Any])
        upd(&qwen, models["qwen"] as? [String: Any])
        return true
    }
}

// MARK: - 可續傳下載器

/// 為什麼要自己寫：三個來源服務的是同一顆檔案（SHA256 終驗把關），來源之間用 Range 無縫接力；
/// 多輪輪替（每輪把所有來源試一遍、輪間指數退避）；停滯看門狗（不論哪種黑洞，
/// stallSeconds 沒收到位元組就砍掉換下一個）。系統的 resumeData 綁單一來源，換來源就歸零重來。
final class ModelDownload: NSObject, URLSessionDataDelegate {
    enum Phase: Equatable { case downloading, verifying, done, failed(String) }

    let spec: ModelCatalog.Spec
    let dest: URL
    private let sources: [URL]
    private let done: (Result<String, Error>) -> Void

    static var stallSeconds: TimeInterval = 45
    static var maxRounds = 6
    static var backoffCapSeconds: TimeInterval = 30

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var out: FileHandle?
    private var offset: Int64 = 0  // .part 已有的位元組＝Range 起點
    private var round = 1
    private var sourceIndex = 0
    private var finished = false
    private var cancelledByUser = false
    private var lastReason = "未知錯誤"
    private var watchdog: DispatchSourceTimer?
    private let lock = NSLock()
    private var lastActivity = Date()
    private var pendingFailReason: String?
    private var verifyOnCancel = false  // 416 且 .part 已完整：cancel 後直接進驗證

    private(set) var fraction: Double = 0
    private(set) var phase: Phase = .downloading
    private(set) var bytesWritten: Int64 = 0

    private static var workDir: URL {
        SharedPaths.support.appendingPathComponent("downloads", isDirectory: true)
    }
    private var partFile: URL { Self.workDir.appendingPathComponent(spec.file + ".part") }

    @discardableResult
    static func start(_ spec: ModelCatalog.Spec, done: @escaping (Result<String, Error>) -> Void)
        -> ModelDownload
    {
        let d = ModelDownload(spec: spec, done: done)
        d.begin()
        return d
    }

    private init(spec: ModelCatalog.Spec, done: @escaping (Result<String, Error>) -> Void) {
        self.spec = spec
        self.dest = SharedPaths.downloadDestination(spec.file)
        self.sources = ModelCatalog.downloadSources(spec)
        self.done = done
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 6 * 3600
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = true  // 斷網等網路回來；「一直等」的黑洞由看門狗收拾
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1  // delegate 序列化＝FileHandle 寫入不打架
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: q)
    }

    private func begin() {
        let fm = FileManager.default
        guard !sources.isEmpty else {
            finish(.failure(TalkyError("沒有可用的下載來源")))
            return
        }
        try? fm.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.workDir, withIntermediateDirectories: true)
        if let msg = Self.diskShortfallMessage(need: spec.bytes) {
            finish(.failure(TalkyError(msg)))
            return
        }
        if !fm.fileExists(atPath: partFile.path) { fm.createFile(atPath: partFile.path, contents: nil) }
        offset = (try? fm.attributesOfItem(atPath: partFile.path))?[.size] as? Int64 ?? 0
        if spec.bytes <= 0 || offset > spec.bytes { offset = 0 }
        guard let h = try? FileHandle(forWritingTo: partFile) else {
            finish(.failure(TalkyError("無法寫入下載暫存檔")))
            return
        }
        out = h
        try? h.truncate(atOffset: UInt64(offset))
        _ = try? h.seekToEnd()
        bytesWritten = offset
        if spec.bytes > 0 { fraction = min(0.999, Double(offset) / Double(spec.bytes)) }
        if offset > 0 { TalkyLog.write("download resume \(spec.file) offset=\(offset / 1_048_576)MB") }
        startWatchdog()
        attempt()
    }

    private func attempt() {
        guard !finished, !cancelledByUser else { return }
        let url = sources[sourceIndex]
        lock.withLock {
            lastActivity = Date()
            pendingFailReason = nil
            verifyOnCancel = false
        }
        var req = URLRequest(url: url)
        if offset > 0 { req.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        TalkyLog.write(
            "download attempt r\(round) s#\(sourceIndex) \(url.host ?? "?") offset=\(offset / 1_048_576)MB")
        task = session.dataTask(with: req)
        task?.resume()
    }

    private func attemptFailed(_ reason: String) {
        guard !finished, !cancelledByUser else { return }
        TalkyLog.write("download fail r\(round) s#\(sourceIndex): \(reason)")
        lastReason = reason
        sourceIndex += 1
        if sourceIndex < sources.count {
            attempt()
            return
        }
        sourceIndex = 0
        round += 1
        guard round <= Self.maxRounds else {
            finish(
                .failure(
                    TalkyError(
                        "下載失敗：所有來源輪流試了 \(Self.maxRounds) 輪（最後原因：\(lastReason)）。已下載的部分有保留，按重試會從斷點接續"
                    )))
            return
        }
        let delay = min(Self.backoffCapSeconds, pow(2, Double(round - 1)))
        TalkyLog.write("download round \(round)/\(Self.maxRounds) in \(Int(delay))s")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attempt()
        }
    }

    /// 使用者按取消：.part 留著（下次啟動從斷點接）
    func cancel() {
        cancelledByUser = true
        task?.cancel()
        watchdog?.cancel()
        try? out?.synchronize()
    }
    func persistForQuit() { cancel() }

    private func truncatePart() {
        try? out?.truncate(atOffset: 0)
        offset = 0
        bytesWritten = 0
        fraction = 0
    }

    private func startWatchdog() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            guard let self, !self.finished, !self.cancelledByUser else { return }
            guard let task = self.task, task.state == .running else { return }
            let stalled: Bool = self.lock.withLock {
                Date().timeIntervalSince(self.lastActivity) > Self.stallSeconds
            }
            guard stalled else { return }
            self.lock.withLock {
                self.pendingFailReason = "來源停滯（\(Int(Self.stallSeconds)) 秒沒有任何資料）"
            }
            task.cancel()
        }
        t.activate()
        watchdog = t
    }

    // ── delegate ──
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !finished else { return completionHandler(.cancel) }
        lock.withLock { lastActivity = Date() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 206:
            let cr =
                ((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range")) ?? ""
            let start =
                Int64(cr.dropFirst("bytes ".count).split(separator: "-").first.map(String.init) ?? "")
                ?? -1
            if start != offset {
                truncatePart()
                lock.withLock { pendingFailReason = "續傳起點不符（來源回 \(start)、應為 \(offset)）" }
                return completionHandler(.cancel)
            }
            completionHandler(.allow)
        case 200:
            if offset > 0 {
                TalkyLog.write("download s#\(sourceIndex) 不支援續傳，整檔重收")
                truncatePart()
            }
            completionHandler(.allow)
        case 416:
            if spec.bytes > 0, offset >= spec.bytes {
                lock.withLock { verifyOnCancel = true }
            } else {
                truncatePart()
                lock.withLock { pendingFailReason = "伺服器回應 416" }
            }
            completionHandler(.cancel)
        default:
            lock.withLock { pendingFailReason = "伺服器回應 \(status)" }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished, let out else { return }
        lock.withLock { lastActivity = Date() }
        do { try out.write(contentsOf: data) } catch {
            lock.withLock { pendingFailReason = "寫入失敗：\(error.localizedDescription)" }
            dataTask.cancel()
            return
        }
        offset += Int64(data.count)
        bytesWritten = offset
        if spec.bytes > 0 {
            if offset > spec.bytes {
                truncatePart()
                lock.withLock { pendingFailReason = "內容超出預期大小（來源給錯檔）" }
                dataTask.cancel()
                return
            }
            fraction = min(0.999, Double(offset) / Double(spec.bytes))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        if let error {
            let ns = error as NSError
            if cancelledByUser { return }
            let (reason, verify): (String?, Bool) = lock.withLock {
                (pendingFailReason, verifyOnCancel)
            }
            if verify { return verifyAndFinish() }
            if let reason { return attemptFailed(reason) }
            return attemptFailed(ns.localizedDescription)
        }
        if spec.bytes > 0, offset != spec.bytes {
            return attemptFailed(
                "下載中斷（收到 \(offset / 1_048_576)MB／應為 \(spec.bytes / 1_048_576)MB）")
        }
        verifyAndFinish()
    }

    private func verifyAndFinish() {
        guard !finished else { return }
        phase = .verifying
        try? out?.synchronize()
        try? out?.close()
        out = nil
        let size =
            (try? FileManager.default.attributesOfItem(atPath: partFile.path))?[.size] as? Int64 ?? 0
        if spec.bytes > 0, size != spec.bytes {
            reopenPartAfterBadVerify()
            return attemptFailed("下載不完整（\(size / 1_048_576)MB／應為 \(spec.bytes / 1_048_576)MB）")
        }
        if let want = spec.sha256, let got = Self.sha256(of: partFile), got != want {
            TalkyLog.write("download sha256 mismatch \(spec.file) r\(round) s#\(sourceIndex)")
            try? FileManager.default.trashItem(at: partFile, resultingItemURL: nil)
            reopenPartAfterBadVerify()
            return attemptFailed("檔案校驗失敗（內容與官方不符），已丟棄重抓")
        }
        do {
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: partFile)
        } catch {
            finish(.failure(TalkyError("寫入模型檔失敗：\(error.localizedDescription)")))
            return
        }
        fraction = 1
        phase = .done
        TalkyLog.write("download done \(spec.file) \(size) bytes r\(round)")
        finish(.success(dest.path))
    }

    private func reopenPartAfterBadVerify() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: partFile.path) { fm.createFile(atPath: partFile.path, contents: nil) }
        out = try? FileHandle(forWritingTo: partFile)
        try? out?.truncate(atOffset: 0)
        offset = 0
        bytesWritten = 0
        fraction = 0
        phase = .downloading
    }

    private func finish(_ r: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        watchdog?.cancel()
        try? out?.close()
        out = nil
        if case .failure(let e) = r { phase = .failed(e.localizedDescription) }
        session.finishTasksAndInvalidate()
        done(r)
    }

    // ── 工具 ──
    static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = h.readData(ofLength: 4 * 1_048_576)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func diskShortfallMessage(need: Int64) -> String? {
        let url = SharedPaths.support
        guard
            let free = (try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]))?.volumeAvailableCapacityForImportantUsage
        else { return nil }
        let want = need + 500 * 1_048_576
        guard free < want else { return nil }
        let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1_000_000_000) }
        return "磁碟空間不足：這顆模型需要約 \(gb(need))，目前只剩 \(gb(free))。請清出空間後再試"
    }
}
