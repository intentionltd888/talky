// AudioTap — 待命期間一直開著的麥克風
//
// 為什麼一直開著：iOS 規定麥克風只能在 app 前景時「開始」。使用者在別的 App 按鍵盤麥克風時，
// Talky 在背景，沒辦法那時才開。所以待命＝麥克風先開好（背景音訊模式讓 app 活著），
// 沒在聽的時候聲音直接丟掉，只留最近 0.4 秒當「前奏」：按下去的同時就開口，第一個字也不會被切掉。
// 這個類別不碰 UI，也不跑在主執行緒：tap 回呼在音訊執行緒，所以共用狀態都上鎖。

import AVFoundation

final class AudioTap: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var ring: [AVAudioPCMBuffer] = []
    private var ringFrames: AVAudioFrameCount = 0
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var lastLevelAt = Date.distantPast
    private(set) var running = false

    /// 音量 0–1（約每 80ms 一次，任意執行緒）
    var onLevel: ((Float) -> Void)?
    /// 麥克風被系統收走（來電、別的 app 搶走、路由變了又救不回來）
    var onLost: ((String) -> Void)?

    private static let prerollSeconds = 0.4

    /// 只能在前景呼叫
    func start() throws {
        guard !running else { return }
        let s = AVAudioSession.sharedInstance()
        // mixWithOthers：背景音樂照放；A2DP：藍牙耳機照聽歌，收音用手機麥克風（不把耳機切成通話音質）
        try s.setCategory(
            .playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
        try s.setActive(true)
        try installAndStart()
        running = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(configChanged), name: .AVAudioEngineConfigurationChange, object: engine)
    }

    private func installAndStart() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw NSError(domain: "Talky", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到麥克風"])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.handle(buf)
        }
        engine.prepare()
        try engine.start()
    }

    /// 來電等打斷結束後，把麥克風接回來（app 在背景也試；不行就回報失敗，由呼叫端結束待命）
    func resume() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        try installAndStart()
        running = true
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        ring.removeAll()
        ringFrames = 0
        sink = nil
        lock.unlock()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 開始把聲音交出去（先交前奏）
    func beginCapture(_ to: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        let pre = ring
        ring.removeAll()
        ringFrames = 0
        sink = to
        lock.unlock()
        pre.forEach(to)
    }

    func endCapture() {
        lock.lock()
        sink = nil
        lock.unlock()
    }

    // 耳機插拔、藍牙切換會讓 engine 停掉；在背景重開通常還行（session 已經是 active），不行就回報
    @objc private func configChanged() {
        guard running else { return }
        do {
            try installAndStart()
        } catch {
            running = false
            onLost?("麥克風切換後沒接上：\(error.localizedDescription)")
        }
    }

    private func handle(_ buf: AVAudioPCMBuffer) {
        reportLevel(buf)
        lock.lock()
        if let sink {
            lock.unlock()
            sink(buf)
            return
        }
        // 沒在聽：留最近 0.4 秒
        if let copy = buf.copyPCM() {
            ring.append(copy)
            ringFrames += copy.frameLength
            let keep = AVAudioFrameCount(buf.format.sampleRate * Self.prerollSeconds)
            while ringFrames > keep, let first = ring.first {
                ringFrames -= first.frameLength
                ring.removeFirst()
            }
        }
        lock.unlock()
    }

    private func reportLevel(_ buf: AVAudioPCMBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelAt) > 0.08, let ch = buf.floatChannelData?[0] else { return }
        lastLevelAt = now
        let n = Int(buf.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        // -50dB → 0、-10dB → 1
        let db = 20 * log10(max(rms, 1e-6))
        onLevel?(min(1, max(0, (db + 50) / 40)))
    }
}

extension AVAudioPCMBuffer {
    /// tap 給的 buffer 會被引擎回收重用，留下來的要自己複製一份
    func copyPCM() -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        out.frameLength = frameLength
        let n = Int(frameLength)
        let chans = Int(format.channelCount)
        if let src = floatChannelData, let dst = out.floatChannelData {
            for c in 0..<chans { dst[c].update(from: src[c], count: n) }
        } else if let src = int16ChannelData, let dst = out.int16ChannelData {
            for c in 0..<chans { dst[c].update(from: src[c], count: n) }
        } else if let src = int32ChannelData, let dst = out.int32ChannelData {
            for c in 0..<chans { dst[c].update(from: src[c], count: n) }
        } else {
            return nil
        }
        return out
    }
}
