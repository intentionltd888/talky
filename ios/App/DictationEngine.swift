// DictationEngine — 主 app 的聽寫狀態機（待命 → 聽 → 整理 → 交給鍵盤）
//
// 流程（跟 Typeless／Wispr 的 iPhone 版同一招，因為 iOS 鍵盤不能開麥克風）：
// 1. 鍵盤按麥克風，Talky 沒在待命 → 鍵盤用 talky://listen 叫醒 app → app 在前景開麥克風並立刻開始聽
// 2. 使用者點左上角「◀ 返回」回到原本的 App，繼續講；鍵盤上看得到即時字幕
// 3. 鍵盤按停 → app（在背景）收尾辨識、整理 → 寫進 state.json → 鍵盤把字打進游標
// 4. 之後 N 分鐘內（待命）再按麥克風，不用再跳 app
// 所有狀態都寫進 App Group 的 state.json，並用 Darwin 通知叫鍵盤來讀（見 Shared/Bridge.swift）。

import ActivityKit
import AVFoundation
import FoundationModels
import Speech
import SwiftUI

@MainActor
final class DictationEngine: ObservableObject {
    static let shared = DictationEngine()

    @Published private(set) var state = LiveState()
    /// 這次是被鍵盤叫醒的（顯示「回到剛剛的 App」那頁）
    @Published var showBounce = false
    /// 第一次下載中文語音模型的進度（nil＝沒在下載）
    @Published private(set) var assetProgress: Double?
    @Published private(set) var lastOutcome: PolishOutcome?
    /// 用相機掃了 Mac 的 QR 碼（talky://pair）之後的一句話（首頁跳提示）
    @Published var pairNotice: String?

    private let audio = AudioTap()
    private let listener = SignalListener()
    private var live: LiveTranscriber?
    private var keepAliveTimer: Timer?
    private var lastPartialPublish = Date.distantPast
    private var workTask: Task<Void, Never>?
    private var listenStartedAt: Date?
    /// 這一句要翻成什麼（鍵盤長按選的；開始聽時從 App Group 取走）
    private var turnOutput: Translate.Target?
    /// 動態島／鎖定畫面上的 Talky（待命期間一直掛著；從控制中心開的待命，Apple 規定一定要有）
    private var activity: Activity<TalkyActivityAttributes>?
    private var activityState: TalkyActivityAttributes.ContentState?
    private var activityUpdatedAt = Date.distantPast

    private init() {
        // 上一個行程可能被系統收掉，檔案還寫著「待命中」：一律從 off 開始
        var s = LiveState.load()
        s.phase = s.phase == .done ? .done : .off
        s.readyUntil = nil
        s.partial = ""
        s.level = 0
        // 上次的提示（「沒聽到內容」之類）不帶到新的一次啟動
        if s.phase != .done { s.message = nil }
        state = s
        Bridge.log("app", "啟動")
        publish()
        // 上一個行程留下的動態島（被系統收掉時來不及關）一律收掉
        Task {
            for a in Activity<TalkyActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }

        listener.on(.start) { [weak self] in self?.startListening(target: .keyboard) }
        listener.on(.stop) { [weak self] in self?.stopListening() }
        listener.on(.cancel) { [weak self] in self?.cancelListening() }
        listener.on(.ping) { [weak self] in
            if self?.audio.running == true { Bridge.post(.pong) }
        }
        listener.on(.consumed) { [weak self] in self?.resultConsumed() }

        audio.onLevel = { [weak self] lv in
            DispatchQueue.main.async { self?.levelChanged(lv) }
        }
        audio.onLost = { [weak self] why in
            DispatchQueue.main.async { self?.sessionLost(why) }
        }
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    self?.interruptionBegan()
                } else if raw == AVAudioSession.InterruptionType.ended.rawValue {
                    self?.interruptionEnded()
                }
            }
        }
        nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionLost("系統音訊重置，待命結束") }
        }
    }

    var sessionRunning: Bool { audio.running }

    // MARK: 進入點

    /// talky://listen（鍵盤叫醒）
    func handle(url: URL) {
        guard url.scheme == "talky" else { return }
        if url.host == "pair" {
            switch MacRelay.pair(from: url) {
            case .success(let p):
                Settings.polishMode = .claude
                pairNotice = "已配對「\(p.name)」：之後整理與翻譯會用那台 Mac 登入的訂閱。"
                // 趁在前景先連一次：iOS 第一次連區網會問權限，要讓人當場按「允許」
                Task { _ = try? await MacRelay.call(["op": "status"], timeout: 8) }
            case .failure(let e):
                pairNotice = "沒配對成功：\(e.localizedDescription)"
            }
            return
        }
        if url.host == "listen" {
            Bridge.log("app", "被鍵盤叫醒（talky://listen），待命中＝\(audio.running)")
            showBounce = true
            Task { await beginSession(listenFor: .keyboard) }
        }
    }

    /// 開始待命（前景才能呼叫）；listenFor 有值就順便直接開始聽
    func beginSession(listenFor target: LiveState.Target? = nil) async {
        Bridge.log("app", "開始待命，順便聽＝\(target?.rawValue ?? "否")")
        guard await Permissions.request() else {
            fail("需要麥克風權限：設定 → Talky → 麥克風")
            return
        }
        if !audio.running {
            do {
                try audio.start()
            } catch {
                fail("麥克風打不開：\(error.localizedDescription)")
                return
            }
        }
        extendKeepAlive()
        if state.phase == .off || state.phase == .failed {
            state.phase = .ready
            state.message = nil
            publish()
        }
        if let target { startListening(target: target) }
        // 模型準備與預熱放在後面，不擋收音（每句開始前會等模型好；先收的聲音排隊）
        LiveTranscriber.onProgress = { p in
            Task { @MainActor in self.assetProgress = p < 1 ? p : nil }
        }
        do {
            try await LiveTranscriber.ensureAssets()
            assetProgress = nil
        } catch {
            assetProgress = nil
            fail("中文語音模型下載失敗：\(error.localizedDescription)（連上網路再試一次）")
        }
        await Polisher.shared.prewarm()
    }

    func endSession() {
        Bridge.log("app", "結束待命")
        workTask?.cancel()
        if let live { Task { await live.cancel() } }
        live = nil
        audio.stop()
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        state.phase = .off
        state.readyUntil = nil
        state.partial = ""
        state.level = 0
        publish()
    }

    // MARK: 聽

    func startListening(target: LiveState.Target) {
        Bridge.log("app", "開始聽 target=\(target.rawValue) 麥克風開著＝\(audio.running) phase=\(state.phase.rawValue)")
        guard audio.running else {
            // 鍵盤以為 app 醒著但其實睡了：狀態寫 off，鍵盤看到會改成叫醒 app
            state.phase = .off
            state.message = "待命已結束，再按一次麥克風"
            publish()
            return
        }
        guard state.phase != .listening, state.phase != .working else { return }
        workTask?.cancel()
        let lt = LiveTranscriber(glossary: Settings.glossaryTerms)
        lt.onText = { [weak self] t in
            DispatchQueue.main.async { self?.partialChanged(t) }
        }
        live = lt
        audio.beginCapture { [weak lt] buf in lt?.feed(buf) }
        state.phase = .listening
        state.target = target
        state.partial = ""
        state.result = nil
        state.raw = nil
        state.path = nil
        state.back = nil
        state.lang = nil
        state.hold = nil
        state.message = nil
        turnOutput = Translate.takeNext()
        state.out = turnOutput?.key
        if let t = turnOutput { Bridge.log("app", "這句翻成 \(t.key)") }
        listenStartedAt = Date()
        extendKeepAlive()
        publish()
        Task {
            do {
                try await lt.start()
            } catch {
                if self.live === lt { self.fail("辨識沒啟動：\(error.localizedDescription)") }
            }
        }
    }

    func stopListening() {
        Bridge.log("app", "停止聽 phase=\(state.phase.rawValue) 有辨識器＝\(live != nil)")
        guard state.phase == .listening, let lt = live else { return }
        audio.endCapture()
        state.phase = .working
        state.level = 0
        publish()
        let target = state.target
        let out = turnOutput
        workTask = Task {
            let heard = await lt.finish()
            if self.live === lt { self.live = nil }
            let raw = TextRules.fixASR(heard.trimmingCharacters(in: .whitespacesAndNewlines))
            Bridge.log("app", "辨識完 \(raw.count) 字")
            if raw.isEmpty || TextRules.isHallucination(raw) {
                self.state.phase = self.audio.running ? .ready : .off
                self.state.partial = ""
                self.state.message = "沒聽到內容"
                self.publish()
                return
            }
            self.state.partial = raw
            self.publish()
            let outcome = await Polisher.shared.process(raw, out: out)
            guard !Task.isCancelled else { return }
            self.deliver(outcome, raw: raw, target: target)
        }
    }

    func cancelListening() {
        guard state.phase == .listening || state.phase == .working else { return }
        audio.endCapture()
        workTask?.cancel()
        if let lt = live { Task { await lt.cancel() } }
        live = nil
        state.phase = audio.running ? .ready : .off
        state.partial = ""
        state.level = 0
        publish()
    }

    private func deliver(_ o: PolishOutcome, raw: String, target: LiveState.Target) {
        Bridge.log("app", "整理完 path=\(o.path) \(o.text.count) 字 target=\(target.rawValue)\(o.note.map { "（\($0)）" } ?? "")")
        lastOutcome = o
        // 翻譯時「原文」＝整理好的中文（鍵盤那顆變成「中文」）；沒翻譯＝只加標點的原話
        let plain = o.zh ?? TextRules.light(raw)
        Memo.shared.add(text: o.text, raw: plain, path: o.path, lang: o.lang)
        state.phase = .done
        state.target = target
        state.resultID = UUID().uuidString
        state.result = o.text
        state.raw = plain
        state.back = o.back
        state.lang = o.lang
        state.hold = o.hold ? true : nil
        state.path = o.path
        state.message = o.note
        state.partial = ""
        extendKeepAlive()
        publish()
    }

    /// 鍵盤貼好了 → 回到待命
    private func resultConsumed() {
        Bridge.log("app", "鍵盤說已貼上")
        guard state.phase == .done else { return }
        state.phase = audio.running ? .ready : .off
        publish()
    }

    // MARK: 待命計時

    private func extendKeepAlive() {
        let m = Settings.keepAliveMinutes
        state.readyUntil = m == 0 ? Date.distantFuture : Date().addingTimeInterval(Double(m) * 60)
        if keepAliveTimer == nil {
            keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkKeepAlive() }
            }
        }
    }

    private func checkKeepAlive() {
        guard audio.running else { return }
        if state.phase == .listening || state.phase == .working { return }
        if let until = state.readyUntil, until < Date() { endSession() }
    }

    // 來電、Siri 打斷：講到一半的先整理出去；打斷結束自己把麥克風接回來，不用再跳 app
    private var interrupted = false

    private func interruptionBegan() {
        Bridge.log("app", "被打斷（來電／Siri）")
        guard audio.running else { return }
        interrupted = true
        if state.phase == .listening { stopListening() }
        state.message = "被來電打斷；結束後會自己回到待命"
        publish()
    }

    private func interruptionEnded() {
        Bridge.log("app", "打斷結束，接回麥克風")
        guard interrupted else { return }
        interrupted = false
        do {
            try audio.resume()
            if state.phase == .off || state.phase == .failed { state.phase = .ready }
            state.message = nil
            extendKeepAlive()
            publish()
        } catch {
            sessionLost("打斷後麥克風接不回來：打開 Talky 就會重新待命")
        }
    }

    /// 控制中心／動作按鈕／Siri（StartStandbyIntent）叫的：Talky 在背景，不能問權限、不跳畫面
    func armFromIntent() async {
        Bridge.log("app", "控制中心／動作按鈕開待命")
        guard Permissions.micGranted else {
            state.message = "第一次要先打開 Talky 允許麥克風"
            publish()
            return
        }
        if !audio.running {
            do {
                try audio.start()
            } catch {
                fail("麥克風打不開：\(error.localizedDescription)")
                return
            }
        }
        extendKeepAlive()
        if state.phase == .off || state.phase == .failed {
            state.phase = .ready
            state.message = nil
        }
        publish()
        try? await LiveTranscriber.ensureAssets()
        await Polisher.shared.prewarm()
    }

    /// 打開 Talky（到前景）就自動待命：不用按「開始待命」，之後鍵盤都在原地講
    func autoArm() {
        guard !audio.running, Permissions.micGranted else { return }
        Task { await beginSession() }
    }

    private func sessionLost(_ why: String) {
        guard audio.running || state.phase != .off else { return }
        if state.phase == .listening, let lt = live {
            // 聽到一半被打斷：已經聽到的先整理出去，不讓話白講
            audio.endCapture()
            state.phase = .working
            publish()
            let target = state.target
            let out = turnOutput
            workTask = Task {
                let raw = TextRules.fixASR(await lt.finish().trimmingCharacters(in: .whitespacesAndNewlines))
                self.live = nil
                self.audio.stop()
                if !raw.isEmpty {
                    let o = await Polisher.shared.process(raw, out: out)
                    self.deliver(o, raw: raw, target: target)
                }
                self.state.readyUntil = nil
                if self.state.phase != .done { self.state.phase = .off }
                self.state.message = why
                self.publish()
            }
            return
        }
        endSession()
        state.message = why
        publish()
    }

    private func fail(_ msg: String) {
        Bridge.log("app", "出錯：\(msg)")
        state.phase = audio.running ? .ready : .failed
        state.message = msg
        state.partial = ""
        publish()
    }

    // MARK: 發布

    private func partialChanged(_ t: String) {
        guard state.phase == .listening else { return }
        state.partial = t
        let now = Date()
        if now.timeIntervalSince(lastPartialPublish) > 0.12 {
            lastPartialPublish = now
            publish()
        }
    }

    private func levelChanged(_ lv: Float) {
        guard state.phase == .listening else { return }
        state.level = lv
        let now = Date()
        if now.timeIntervalSince(lastPartialPublish) > 0.12 {
            lastPartialPublish = now
            publish()
        }
    }

    private func publish() {
        state.stamp = Date()
        state.save()
        Bridge.post(.state)
        syncActivity()
    }

    // MARK: 動態島

    private var loggedActivityOff = false
    private func syncActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            if !loggedActivityOff {
                loggedActivityOff = true
                Bridge.log("app", "即時動態被關掉了（設定 → Talky → 即時動態）")
            }
            return
        }
        let content = TalkyActivityAttributes.ContentState(phase: state.phase.rawValue, line: activityLine())
        if audio.running {
            if activity == nil {
                // 前景、或控制中心的意圖裡才開得起來；其他時候失敗就算了（下次到前景會補開）
                do {
                    activity = try Activity.request(
                        attributes: TalkyActivityAttributes(), content: .init(state: content, staleDate: nil))
                    Bridge.log("app", "動態島開了")
                } catch {
                    Bridge.log("app", "動態島開不起來：\(error)")
                }
                activityState = content
                activityUpdatedAt = Date()
            } else if content != activityState,
                content.phase != activityState?.phase || Date().timeIntervalSince(activityUpdatedAt) > 1
            {
                // 換狀態馬上更新；字幕一秒最多更新一次（動態島有更新頻率上限）
                activityState = content
                activityUpdatedAt = Date()
                let a = activity
                Task { await a?.update(.init(state: content, staleDate: nil)) }
            }
        } else if let a = activity {
            activity = nil
            activityState = nil
            Task { await a.end(.init(state: content, staleDate: nil), dismissalPolicy: .immediate) }
        }
    }

    private func activityLine() -> String {
        switch state.phase {
        case .listening:
            let head = state.out.flatMap(Translate.Target.init(key:)).map { "翻成\($0.label)：" } ?? ""
            return head + (state.partial.isEmpty ? "正在聽…" : state.partial)
        case .working:
            if let t = state.out.flatMap(Translate.Target.init(key:)) { return "翻成\(t.label)…" }
            return state.partial.isEmpty ? "整理中…" : state.partial
        case .done: return state.result ?? "好了"
        default: return "待命中：任何 App 的 Talky 鍵盤都能直接講"
        }
    }

    #if DEBUG
    /// 開發用：拿音檔走跟麥克風完全一樣的辨識＋整理路徑（真機自動測試用；見 scripts/device-test.sh）
    /// 用法：xcrun devicectl device process launch --console --terminate-existing --device <手機> ltd.intention.talky.ios \\
    ///       -- -TalkyFeedFile <Documents 裡的檔名或絕對路徑> [-TalkyExitAfterTest]（app 參數前一定要有 --）
    /// 每一步印在 console（前綴 TALKY-TEST）並寫 Documents/diag.txt。結果標成 app 自己的（鍵盤不會自動貼）。
    /// 開發用參數（寫進設定，等於在首頁／鍵盤上選）：-TalkyPolishMode、-TalkyTranslate、-TalkySpeaker
    func debugApplyArgs() {
        let args = ProcessInfo.processInfo.arguments
        Bridge.shared.set(args.contains("-TalkyDebugPicker"), forKey: "debugOpenPicker")
        // -TalkyPairLink talky://pair?…：測試用，等於用相機掃了 Mac 的 QR 碼
        if let j = args.firstIndex(of: "-TalkyPairLink"), j + 1 < args.count, let u = URL(string: args[j + 1]) {
            if case .failure(let e) = MacRelay.pair(from: u) { print("TALKY-TEST pair error=\(e.localizedDescription)") }
        }
        // -TalkyUnpair：解除配對（測試完清掉測試中繼）
        if args.contains("-TalkyUnpair") { MacRelay.unpair() }
        // -TalkyMacBrain claude|codex|mac：指定配對 Mac 用哪一顆
        if let j = args.firstIndex(of: "-TalkyMacBrain"), j + 1 < args.count {
            Settings.macBrain = args[j + 1] == "mac" ? "" : args[j + 1]
        }
        // -TalkyPolishMode apple|claude|off：測試指定整理方式（會寫進設定，等於在首頁切換）
        if let j = args.firstIndex(of: "-TalkyPolishMode"), j + 1 < args.count, let m = PolishMode(rawValue: args[j + 1]) {
            Settings.polishMode = m
        }
        // -TalkyTranslate th:girl | ja:client …：下一句翻成它（等於在鍵盤長按選了這個目標）
        if let j = args.firstIndex(of: "-TalkyTranslate"), j + 1 < args.count {
            Translate.setNext(Translate.Target(key: args[j + 1]))
        }
        // -TalkySpeaker male|female|unset
        if let j = args.firstIndex(of: "-TalkySpeaker"), j + 1 < args.count, let v = SpeakerVoice(rawValue: args[j + 1]) {
            Translate.speaker = v
        }
    }

    func debugFeedIfAsked() {
        debugApplyArgs()
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-TalkyFeedFile"), i + 1 < args.count else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = args[i + 1]
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : docs.appendingPathComponent(name)
        let exitAfter = args.contains("-TalkyExitAfterTest")
        var lines: [String] = []
        func note(_ s: String) {
            print("TALKY-TEST \(s.replacingOccurrences(of: "\n", with: "⏎"))")
            lines.append(s)
            try? lines.joined(separator: "\n").write(
                to: docs.appendingPathComponent("diag.txt"), atomically: true, encoding: .utf8)
        }
        let testOut = Translate.takeNext()
        Task {
            let t0 = Date()
            note(
                "file=\(url.lastPathComponent) engine=\(LiveTranscriber.engineName) llm=\(SystemLanguageModel.default.availability) mode=\(Settings.polishMode.rawValue)\(Settings.polishMode == .claude ? "/" + Settings.claudeModel : "") out=\(testOut?.key ?? "zh") voice=\(Translate.speaker.rawValue)")
            do {
                try await LiveTranscriber.ensureAssets()
                note(String(format: "assets ok %.2fs", Date().timeIntervalSince(t0)))
                let file = try AVAudioFile(forReading: url)
                let lt = LiveTranscriber(glossary: Settings.glossaryTerms)
                var updates = 0
                lt.onText = { t in
                    updates += 1
                    DispatchQueue.main.async { self.partialChanged(t) }
                }
                live = lt
                state.phase = .listening
                state.target = .app
                state.partial = ""
                state.message = nil
                publish()
                Task {
                    do { try await lt.start() } catch { note("start error=\(error)") }
                }
                let fmt = file.processingFormat
                while file.framePosition < file.length {
                    guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096) else { break }
                    try file.read(into: buf, frameCount: 4096)
                    lt.feed(buf)
                    try await Task.sleep(for: .milliseconds(15))
                }
                let t1 = Date()
                let heard = TextRules.fixASR(await lt.finish().trimmingCharacters(in: .whitespacesAndNewlines))
                live = nil
                note(String(format: "raw %.2fs after audio, %d live updates: ", Date().timeIntervalSince(t1), updates) + heard)
                if heard.isEmpty {
                    fail("測試音檔沒辨識出字")
                } else {
                    let t2 = Date()
                    let o = await Polisher.shared.process(heard, out: testOut)
                    note(String(format: "polished [%@ %.2fs]: ", o.path, Date().timeIntervalSince(t2)) + o.text + (o.note.map { "（\($0)）" } ?? ""))
                    if let b = o.back { note("back: " + b) }
                    if o.lang != nil, let z = o.zh { note("zh: " + z) }
                    deliver(o, raw: heard, target: .app)
                }
            } catch {
                note("error=\(error)")
                fail("測試失敗：\(error.localizedDescription)")
            }
            if exitAfter {
                try? await Task.sleep(for: .milliseconds(300))
                exit(0)
            }
        }
    }
    #endif
}

enum Permissions {
    static var micGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }
    static var speechGranted: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    /// 麥克風是必要的；語音辨識授權順便要（不同 iOS 版本對 SpeechAnalyzer 要不要它說法不一，要了比較穩）
    static func request() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in c.resume() }
            }
        }
        return mic
    }
}
