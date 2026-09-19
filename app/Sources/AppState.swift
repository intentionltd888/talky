// AppState — 兩個視窗共用的狀態源
//
// 每 1.5 秒重算一次（引擎活著沒、權限給了沒、模型在不在），UI 只讀這裡，不各自去問系統。

import AVFoundation
import AppKit
import ServiceManagement
import SwiftUI

final class AppState: ObservableObject {
    static let shared = AppState()

    enum Health {
        case ready  // 就緒
        case starting  // 引擎啟動中
        case dictating  // 聽寫中
        case needsSetup(String)  // 缺東西（模型／權限）
        case broken(String)  // 有問題

        var isProblem: Bool {
            switch self {
            case .needsSetup, .broken: return true
            default: return false
            }
        }
    }

    @Published var health: Health = .starting
    @Published var axTrusted = false
    @Published var micGranted = false
    @Published var whisperModelReady = false
    @Published var polishModelReady = false
    @Published var claudeAvailable = false
    /// 熱鍵監聽真的掛著（有輔助使用權限不等於掛上：部分 macOS 另外要「輸入監控」）
    @Published var hotkeyActive = false
    /// 同一家的會議記錄 app 在跑而且它的輸入法開著＝兩邊搶右 ⌘
    @Published var siblingIMEConflict = false
    @Published var downloadFraction: Double?  // nil＝沒在下載
    @Published var downloadLabel = ""  // 「聽寫模型」／「整理模型」（精靈頁尾與狀態視窗顯示用）
    @Published var downloadNote = ""

    private var timer: Timer?
    private var download: ModelDownload?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.rearmHotkeyIfNeeded()
            self?.refresh()
        }
    }

    /// 權限是使用者在 app 外面（系統設定）給的，app 收不到任何通知：每 tick 對一次，
    /// 給了就掛熱鍵、收回就停。病史＝以前只在啟動與精靈第 2 步呼叫 syncWithSettings，
    /// 使用者後來手動開了輔助使用，app 不重掛，雙擊右 ⌘ 永遠沒反應，要重開 app 才會動。
    /// 放在 timer 而不是 refresh()：syncWithSettings → changed() → refresh() 會互相叫成迴圈。
    private var lastRearmOutcome: Bool?
    private func rearmHotkeyIfNeeded() {
        let dc = DictationController.shared
        let ax = Dictation.axTrusted
        guard ax != dc.hotkeyActive else { return }
        dc.syncWithSettings()
        let outcome = dc.hotkeyActive
        if outcome != lastRearmOutcome {
            TalkyLog.write("hotkey resync: ax=\(ax) → listener \(outcome ? "on" : "off（需輸入監控？）")")
            lastRearmOutcome = outcome
        }
    }

    func refresh() {
        axTrusted = Dictation.axTrusted
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        whisperModelReady = TextUtil.whisperModelPath() != nil
        polishModelReady = LocalLLM.modelReady
        claudeAvailable = ClaudeCLI.available
        hotkeyActive = DictationController.shared.hotkeyActive
        siblingIMEConflict = SharedPaths.siblingAppRunning && SharedPaths.siblingIMEEnabled
        // 給 --doctor 看的（它是另一個行程，看不到這裡的記憶體；而且從終端機跑時 TCC 會把權限算到終端機頭上，
        // 它自己問到的麥克風／輔助使用可能是終端機的答案）：app 每 tick 回寫自己看到的權限與監聽狀態
        let d = UserDefaults.standard
        d.set(hotkeyActive, forKey: "hotkeyListenerOK")
        d.set(axTrusted, forKey: "axTrustedReported")
        d.set(micGranted, forKey: "micGrantedReported")
        d.set(Date().timeIntervalSince1970, forKey: "hotkeyListenerAt")

        if DictationController.shared.isDictating {
            health = .dictating
        } else if !whisperModelReady {
            health = .needsSetup("還缺語音模型")
        } else if TalkyServers.shared.isReady {
            if !axTrusted {
                health = .needsSetup("還沒開輔助使用")
            } else if !hotkeyActive {
                health = .needsSetup("快捷鍵沒接上")
            } else {
                health = .ready
            }
        } else if TalkyServers.shared.isStarting {
            health = .starting
        } else if let e = TalkyServers.shared.lastStartError {
            health = .broken(e)
        } else {
            health = .starting
        }
    }

    /// 一行狀態（狀態視窗最上面那句）
    var headline: String {
        switch health {
        case .ready: return "就緒"
        case .starting: return "語音引擎啟動中…"
        case .dictating: return "聽寫中"
        case .needsSetup(let s): return s
        case .broken(let s): return s
        }
    }

    var subline: String {
        switch health {
        case .ready:
            return "在任何文字框\(Dictation.trigger.longLabel)就能講。"
        case .starting:
            return "第一次要載入模型，約 10 秒。"
        case .dictating:
            return "再\(Dictation.trigger.longLabel)結束。"
        case .needsSetup:
            if !whisperModelReady { return "下載完就能講。" }
            if !axTrusted { return "沒開輔助使用，快捷鍵不會動。開完自動接上。" }
            return "還要開「輸入監控」，下面有按鈕。"
        case .broken:
            return "先按「重啟引擎」。"
        }
    }

    /// 現在用什麼整理
    var polishLabel: String {
        let m = PolishMode.current
        if m == .claudeCLI, ClaudeCLI.coolingDown { return m.label + "（暫時失敗，先走本機）" }
        return m.label
    }

    // ── 動作 ──

    func restartEngines() {
        TalkyServers.shared.stopAll()
        DispatchQueue.global(qos: .userInitiated).async {
            TalkyServers.shared.startAll()
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func downloadWhisperModel() {
        guard download == nil else { return }
        downloadNote = ""
        downloadFraction = 0
        downloadLabel = "聽寫模型"
        let d = ModelDownload.start(ModelCatalog.whisper) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.download = nil
                self.downloadFraction = nil
                switch result {
                case .success:
                    self.downloadNote = "語音模型下載完成"
                    self.restartEngines()
                    self.maybeQueuePolishDownload()
                case .failure(let e):
                    self.downloadNote = e.localizedDescription
                }
                self.refresh()
            }
        }
        download = d
        // 進度回報（下載器自己不發通知，這裡輪詢就夠）
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self, let d = self.download else {
                t.invalidate()
                return
            }
            self.downloadFraction = d.fraction
            if case .verifying = d.phase { self.downloadNote = "校驗中…" }
        }
    }

    /// 精靈替人選了「內建模型」（0.1.2 autoPick）：聽寫模型下載完就接著下載整理模型（下載器單槽，一次一個）；
    /// 磁碟不夠就不下，整理走原稿，狀態視窗那列會寫「還沒下載」。
    func maybeQueuePolishDownload() {
        guard PolishMode.current == .local, !Dictation.lite, !LocalLLM.modelReady, download == nil else { return }
        guard ModelDownload.diskShortfallMessage(need: ModelCatalog.qwen.bytes) == nil else { return }
        TalkyLog.write("whisper done → auto download polish model (autopick local)")
        downloadPolishModel()
    }

    func downloadPolishModel() {
        guard download == nil else { return }
        downloadNote = ""
        downloadFraction = 0
        downloadLabel = "整理模型"
        let d = ModelDownload.start(ModelCatalog.qwen) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.download = nil
                self.downloadFraction = nil
                if case .failure(let e) = result {
                    self.downloadNote = e.localizedDescription
                } else {
                    self.downloadNote = "整理模型下載完成"
                    self.restartEngines()
                }
                self.refresh()
            }
        }
        download = d
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self, let d = self.download else {
                t.invalidate()
                return
            }
            self.downloadFraction = d.fraction
        }
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
        downloadFraction = nil
        downloadNote = "已取消（下次會從斷點接續）"
    }

    func persistDownloadForQuit() { download?.persistForQuit() }

    // ── 開機自啟 ──

    var launchAtLoginOn: Bool {
        SMAppService.mainApp.status == .enabled
    }
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            TalkyLog.write("launch-at-login \(on) fail: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }
}
