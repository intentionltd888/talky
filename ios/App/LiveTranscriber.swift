// LiveTranscriber — 一句話的即時辨識（Apple SpeechAnalyzer，全在手機上）
//
// 為什麼不用 whisper：iOS 26 起系統內建的辨識模型支援 zh-TW、免下載第三方模型、邊講邊出字，
// 而且跑在系統行程裡——Talky 在背景時也能辨識（背景不能用 GPU 跑自己的模型）。
// 一句一個 analyzer：按下去建、講完收；模型留在記憶體（processLifetime），第二句起幾乎零等待。
//
// 兩顆模型：SpeechTranscriber 最準（新模型）；不支援的機型（模擬器實測 isAvailable＝false）
// 退 DictationTranscriber（系統鍵盤聽寫同一顆）。兩顆 API 同形，結果都有 text／isFinal。

import AVFoundation
import Speech

final class LiveTranscriber: @unchecked Sendable {
    static let locale = Locale(identifier: "zh-TW")
    /// 辨識模型要的聲音格式（第一次問系統後記住）
    nonisolated(unsafe) private static var cachedFormat: AVAudioFormat?
    /// 系統認的正式語言標籤（prepareAssets 查到後記住，每句的辨識器都用這個）
    nonisolated(unsafe) private static var resolvedLocale: Locale?

    private enum Module {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
        var any: any SpeechModule {
            switch self {
            case .speech(let t): return t
            case .dictation(let t): return t
            }
        }
    }

    /// 這支手機用哪一顆（給首頁顯示）
    static var engineName: String { SpeechTranscriber.isAvailable ? "Apple 語音模型" : "Apple 聽寫模型" }

    private static func makeModule(_ loc: Locale) -> Module {
        if SpeechTranscriber.isAvailable {
            return .speech(
                SpeechTranscriber(
                    locale: loc, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
                    attributeOptions: []))
        }
        return .dictation(
            DictationTranscriber(
                locale: loc, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: []))
    }

    private static func resolve() async -> Locale {
        if let l = resolvedLocale { return l }
        let l: Locale?
        if SpeechTranscriber.isAvailable {
            l = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        } else {
            l = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
        resolvedLocale = l ?? locale
        return l ?? locale
    }

    private let module: Module
    private let analyzer: SpeechAnalyzer
    private let glossary: [String]
    private let input: AsyncStream<AnalyzerInput>
    private let inputCont: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var target: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var pending: [AVAudioPCMBuffer] = []
    private var finals = ""
    private var volatile = ""
    private var resultsTask: Task<Void, Never>?
    private var finished = false

    /// 目前聽到的全文（任意執行緒）
    var onText: ((String) -> Void)?

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return finals + volatile
    }

    init(glossary: [String]) {
        self.glossary = glossary
        module = Self.makeModule(Self.resolvedLocale ?? Self.locale)
        analyzer = SpeechAnalyzer(
            modules: [module.any],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime))
        (input, inputCont) = AsyncStream<AnalyzerInput>.makeStream()
        target = Self.cachedFormat
    }

    // ── 模型準備：全 app 只跑一次，每一句開始前都等它 ──
    // 病史：第一次按鍵盤時「開始聽」比「訂閱語言＋下載模型」先跑，辨識器啟動失敗、第一句白講。
    // 現在每句的 start() 都先等這一步；等的期間聲音照樣排隊（AsyncStream），一個字都不掉。
    nonisolated(unsafe) private static var prepTask: Task<Void, Error>?
    private static let prepLock = NSLock()
    /// 下載進度（0–1；任意執行緒）
    nonisolated(unsafe) static var onProgress: ((Double) -> Void)?

    static func ensureAssets() async throws {
        let task: Task<Void, Error> = prepLock.withLock {
            if let t = prepTask { return t }
            let t = Task { try await prepareAssets(progress: { p in onProgress?(p) }) }
            prepTask = t
            return t
        }
        do {
            try await task.value
        } catch {
            prepLock.withLock { prepTask = nil }  // 失敗了下次重試（例如剛才沒網路）
            throw error
        }
    }

    /// 模型在不在手機上；不在就下載（第一次用會跑這段，系統管理）。
    /// 一定要先 reserve（訂閱）這個語言，不然系統回「not subscribed to transcription.cmn」
    private static func prepareAssets(progress: ((Double) -> Void)? = nil) async throws {
        let loc = await resolve()
        let m = makeModule(loc).any
        let tag = loc.identifier(.bcp47)
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == tag }) {
            // 名額有上限：滿了就把最舊的一個讓出來（Talky 只用一個語言）
            if reserved.count >= AssetInventory.maximumReservedLocales, let oldest = reserved.first {
                _ = await AssetInventory.release(reservedLocale: oldest)
            }
            _ = try await AssetInventory.reserve(locale: loc)
        }
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [m]) {
            let obs = req.progress.observe(\.fractionCompleted) { p, _ in progress?(p.fractionCompleted) }
            defer { obs.invalidate() }
            try await req.downloadAndInstall()
        }
        if cachedFormat == nil {
            cachedFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [m])
        }
    }

    func start() async throws {
        try await Self.ensureAssets()
        if target == nil {
            let f = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module.any])
            Self.cachedFormat = f
            let queued: [AVAudioPCMBuffer] = lock.withLock {
                target = f
                defer { pending.removeAll() }
                return pending
            }
            queued.forEach { yieldConverted($0) }
        }
        if !glossary.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = glossary
            try? await analyzer.setContext(ctx)
        }
        switch module {
        case .speech(let t):
            resultsTask = Task { [weak self] in
                do {
                    for try await r in t.results { self?.take(String(r.text.characters), final: r.isFinal) }
                } catch {}
            }
        case .dictation(let t):
            resultsTask = Task { [weak self] in
                do {
                    for try await r in t.results { self?.take(String(r.text.characters), final: r.isFinal) }
                } catch {}
            }
        }
        try await analyzer.start(inputSequence: input)
    }

    private func take(_ piece: String, final: Bool) {
        let now: String = lock.withLock {
            if final {
                finals += piece
                volatile = ""
            } else {
                volatile = piece
            }
            return finals + volatile
        }
        onText?(now)
    }

    /// 音訊執行緒呼叫
    func feed(_ buf: AVAudioPCMBuffer) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        if target == nil {
            if let c = buf.copyPCM() { pending.append(c) }
            lock.unlock()
            return
        }
        lock.unlock()
        yieldConverted(buf)
    }

    private func yieldConverted(_ buf: AVAudioPCMBuffer) {
        guard let out = convert(buf) else { return }
        inputCont.yield(AnalyzerInput(buffer: out))
    }

    private func convert(_ buf: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let target else { return nil }
        if buf.format == target { return buf.copyPCM() }
        if converter == nil || converter?.inputFormat != buf.format {
            converter = AVAudioConverter(from: buf.format, to: target)
            converter?.primeMethod = .none
        }
        guard let conv = converter else { return nil }
        let ratio = target.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        let status = conv.convert(to: out, error: &err) { _, st in
            if fed {
                st.pointee = .noDataNow
                return nil
            }
            fed = true
            st.pointee = .haveData
            return buf
        }
        if status == .error || out.frameLength == 0 { return nil }
        return out
    }

    /// 講完：把剩下的聲音辨識完，回傳全文。
    /// 最多等 6 秒：辨識器沒啟動成功時結果串流永遠不會結束，不設上限鍵盤會永遠停在「整理中」（模擬器實測）
    func finish() async -> String {
        lock.withLock { finished = true }
        inputCont.finish()
        let analyzer = self.analyzer
        let results = resultsTask
        let done = await withTimeout(6) { () async -> Bool in
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
            _ = await results?.value
            return true
        }
        if done == nil {
            resultsTask?.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
        return text
    }

    func cancel() async {
        lock.withLock { finished = true }
        inputCont.finish()
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
    }
}
