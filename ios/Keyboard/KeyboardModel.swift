// KeyboardModel — 鍵盤這一側的狀態與動作
//
// 真相在主 app 寫的 state.json；這裡讀它、顯示它，並把「開始／停止」傳回去。
// 主 app 是不是醒著：出現時 ping 一次，有 pong 才算（檔案可能是上一個行程留下的舊狀態）。

import SwiftUI
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var phase: LiveState.Phase = .off
    @Published var partial = ""
    @Published var level: Float = 0
    @Published var notice: String?
    @Published var fullAccess = true
    @Published var needsGlobe = false
    @Published var appAlive = false
    @Published var returnKeyLabel = "換行"
    /// 設定裡排好的翻譯目標（長按圓鈕時照順序排開）
    @Published private(set) var targets: [Translate.Target] = []
    /// 長按中：正在挑翻譯目標；hover＝手指停在第幾個（nil＝沒停在任何一個，放開＝取消）
    @Published private(set) var choosing = false
    @Published private(set) var hover: Int?
    /// 這一句要翻成什麼（nil＝中文）；聽與整理時狀態列顯示「翻成泰文・女生朋友」
    @Published private(set) var turnOut: Translate.Target?
    /// 剛打進去的是翻譯：譯文直譯回中文（狀態列顯示「意思：…」）
    @Published private(set) var lastBack: String?
    @Published private(set) var lastLang: String?
    /// 剛打進去的那句（可以復原／換原文）。
    /// 同步存進共用設定：備忘錄這類 App 打完字會重建鍵盤（真機實測），重建後靠它把「復原／原文」接回來
    @Published private(set) var lastInsert: (text: String, raw: String?)? {
        didSet {
            if let li = lastInsert {
                Bridge.shared.set(
                    ["text": li.text, "raw": li.raw ?? "", "at": Date().timeIntervalSince1970], forKey: "lastInsert")
            } else {
                Bridge.shared.removeObject(forKey: "lastInsert")
            }
        }
    }
    /// 太久以前整理好、沒貼的那句（不自動貼，給使用者自己點）
    @Published private(set) var pending: (id: String, text: String, raw: String?)?

    var proxy: () -> UITextDocumentProxy? = { nil }
    var openHostApp: () -> Bool = { false }
    var nextKeyboard: () -> Void = {}

    private var listener: SignalListener?
    private var poll: Timer?
    private var deleteRepeat: Timer?
    private var startWatchdog: Task<Void, Never>?
    // 三種震動：開始聽（中）、講完（輕）、字打上了（成功）——不看螢幕也知道到哪一步
    private let hapticStart = UIImpactFeedbackGenerator(style: .medium)
    private let hapticStop = UIImpactFeedbackGenerator(style: .light)
    private let hapticDone = UINotificationFeedbackGenerator()
    private let hapticPick = UISelectionFeedbackGenerator()
    /// 鍵盤正在畫面上（跳去 Talky 成功的話，鍵盤會先消失）
    private var visible = false
    /// 同一個鍵盤行程裡可能同時活著好幾個實例（換 App、App 被關時舊的不一定收得乾淨）。
    /// 只有最後出現的那個能打字：舊實例的輸入框已經不在，讓它領走整理好的字＝那句話就消失了
    /// （模擬器抓到過：舊實例把譯文「打」進已經不存在的輸入框，新實例看到已領走就不打）
    private let instanceID = UUID()
    private static var activeInstance: UUID?
    private var isActive: Bool { Self.activeInstance == instanceID }

    // MARK: 出現／消失

    func appear(fullAccess: Bool, needsGlobe: Bool) {
        visible = true
        Self.activeInstance = instanceID
        Bridge.log("kb", "出現 完整取用＝\(fullAccess)")
        self.fullAccess = fullAccess
        self.needsGlobe = needsGlobe
        guard fullAccess else { return }
        targets = Translate.targets
        #if DEBUG
        // 開發用：模擬器截圖要看「長按挑翻譯目標」的畫面（app 用 -TalkyDebugPicker 開）
        if Bridge.shared.bool(forKey: "debugOpenPicker") {
            choosing = true
            hover = targets.isEmpty ? nil : 0
        }
        #endif
        // 讓主 app 知道：鍵盤加好了、完整取用也開了（首頁設定三步會打勾）
        Bridge.shared.set(Date().timeIntervalSince1970, forKey: "keyboardFullAccessAt")
        let l = SignalListener()
        l.on(.state) { [weak self] in self?.refresh() }
        l.on(.pong) { [weak self] in
            if self?.appAlive == false { Bridge.log("kb", "收到 pong：Talky 醒著") }
            self?.appAlive = true
        }
        listener = l
        appAlive = false
        Bridge.post(.ping)
        restoreLastInsert()
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.phase == .listening || self.phase == .working { self.refresh() }
            }
        }
        hapticStart.prepare()
        hapticDone.prepare()
    }

    private func restoreLastInsert() {
        guard lastInsert == nil, let d = Bridge.shared.dictionary(forKey: "lastInsert"),
            let text = d["text"] as? String, let at = d["at"] as? Double,
            Date().timeIntervalSince1970 - at < 60,
            let before = proxy()?.documentContextBeforeInput, before.hasSuffix(text)
        else { return }
        let raw = d["raw"] as? String
        lastInsert = (text, (raw?.isEmpty ?? true) ? nil : raw)
        Bridge.log("kb", "鍵盤重建後接回「復原／原文」")
    }

    func disappear() {
        visible = false
        choosing = false
        hover = nil
        poll?.invalidate()
        poll = nil
        stopDeleteRepeat()
        listener = nil
    }

    // MARK: 讀狀態

    func refresh() {
        guard isActive else { return }
        let s = LiveState.load()
        phase = s.phase
        partial = s.partial
        level = s.level
        notice = s.message
        if s.sessionAlive && s.phase != .off { appAlive = true }
        if s.phase == .off { appAlive = false }

        if s.phase == .listening || s.phase == .working {
            startWatchdog?.cancel()
            // 被叫醒後重建的鍵盤實例不知道剛剛挑了什麼：以 app 寫的為準
            turnOut = s.out.flatMap(Translate.Target.init(key:))
        }

        if s.phase == .done, s.target == .keyboard, let id = s.resultID, let text = s.result,
            id != Bridge.consumedResultID
        {
            if s.hold == true {
                // 翻譯沒成功、只有中文：不自動打（免得中文誤傳給外國客戶），留給人按「貼中文」
                if pending?.id != id { Bridge.log("kb", "翻譯沒成功，中文留著手動貼") }
                pending = (id, text, s.raw)
                if phase != .listening { phase = .ready }
            } else if Date().timeIntervalSince(s.stamp) < 120 {
                insertResult(id: id, text: text, raw: s.raw, back: s.back, lang: s.lang)
            } else {
                if pending?.id != id { Bridge.log("kb", "有一句太久沒貼（>120 秒），改成手動貼") }
                pending = (id, text, s.raw)
            }
        }
    }

    // MARK: 麥克風

    private func stopListening() {
        hapticStop.impactOccurred()
        phase = .working
        Bridge.post(.stop)
    }

    func micTapped() {
        Bridge.log("kb", "點圓鈕 phase=\(phase.rawValue) Talky 醒著＝\(appAlive)")
        guard fullAccess else {
            notice = "先到 設定 → 一般 → 鍵盤 → 鍵盤 → Talky → 允許完整取用"
            return
        }
        switch phase {
        case .listening:
            stopListening()
        case .working:
            break
        default:
            start(nil)
        }
    }

    /// 開始聽；out＝這一句要翻成什麼（nil＝中文）。先寫進 App Group，app 開始聽時取走
    private func start(_ out: Translate.Target?) {
        lastInsert = nil
        lastBack = nil
        lastLang = nil
        pending = nil
        turnOut = out
        Translate.setNext(out)
        if let out { Bridge.log("kb", "長按選了 \(out.key)") }
        if appAlive {
            hapticStart.impactOccurred()
            phase = .listening
            partial = ""
            Bridge.post(.start)
            // 1.5 秒內主 app 沒回「在聽」＝它其實睡了 → 叫醒
            startWatchdog?.cancel()
            startWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self, !Task.isCancelled else { return }
                let s = LiveState.load()
                if s.phase != .listening && s.phase != .working {
                    Bridge.log("kb", "1.5 秒沒回應，改叫醒 Talky（phase=\(s.phase.rawValue)）")
                    self.appAlive = false
                    self.wakeApp()
                }
            }
        } else {
            wakeApp()
        }
    }

    // MARK: 長按挑翻譯目標（Typeless 同一招：長按圓鈕、往上滑到語言、放開開始講）

    /// 沒在聽、沒在整理、有完整取用才能挑
    var canChoose: Bool { fullAccess && phase != .listening && phase != .working }

    func beginChoosing() {
        guard canChoose, !choosing else { return }
        targets = Translate.targets
        choosing = true
        hover = nil
        hapticPick.prepare()
        hapticStop.impactOccurred()
    }

    /// 手指位置（整個鍵盤的座標）→ 停在第幾個目標：要往上滑進最上面那一條才算
    func hoverAt(_ p: CGPoint, width: CGFloat, bandBottom: CGFloat) {
        guard choosing, !targets.isEmpty else { return }
        var h: Int?
        if p.y < bandBottom {
            let col = Int(p.x / max(1, width / CGFloat(targets.count)))
            h = min(max(col, 0), targets.count - 1)
        }
        if h != hover {
            hover = h
            if h != nil { hapticPick.selectionChanged() }
        }
    }

    /// 放開：停在某個目標上＝開始講、這句翻成它；停在別處＝取消
    func endChoosing() {
        guard choosing else { return }
        let picked = hover.flatMap { targets.indices.contains($0) ? targets[$0] : nil }
        choosing = false
        hover = nil
        if let picked { start(picked) }
    }

    /// 無障礙：不用手勢，直接指定翻成哪個
    func startTranslate(_ t: Translate.Target) {
        guard canChoose else { return }
        start(t)
    }

    private func wakeApp() {
        let failed = "叫不醒 Talky：請先打開 Talky app 按「開始待命」，再回來按"
        let opened = openHostApp()
        Bridge.log("kb", "叫醒 Talky（開網址）\(opened ? "送出" : "失敗")")
        guard opened else {
            notice = failed
            return
        }
        // 開網址這招沒有回報成敗：2 秒後鍵盤還在畫面上＝ Talky 沒被叫起來
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.visible, self.phase != .listening, self.phase != .working else { return }
            self.notice = failed
        }
    }

    func cancelListening() {
        Bridge.post(.cancel)
        phase = .ready
        partial = ""
    }

    // MARK: 打字

    private func insertResult(id: String, text: String, raw: String?, back: String? = nil, lang: String? = nil) {
        // 先確定有輸入框才領走這句；沒有就留著給下一個出現的鍵盤
        guard isActive, let p = proxy() else {
            Bridge.log("kb", "這個鍵盤實例沒有輸入框，這句留著")
            return
        }
        Bridge.log("kb", "打字進游標 \(text.count) 字\(lang.map { "（翻成 \($0)）" } ?? "")")
        Bridge.consumedResultID = id
        Bridge.post(.consumed)
        pending = nil
        p.insertText(text)
        hapticDone.notificationOccurred(.success)
        lastBack = back
        lastLang = lang
        lastInsert = (text, raw)
        phase = .ready
    }

    func insertPending() {
        guard let pd = pending else { return }
        insertResult(id: pd.id, text: pd.text, raw: pd.raw)
    }

    func undo() {
        guard let li = lastInsert, let p = proxy() else { return }
        for _ in 0..<li.text.count { p.deleteBackward() }
        lastInsert = nil
        lastBack = nil
        lastLang = nil
    }

    /// 整理稿換成原話（只加標點）
    func useRaw() {
        guard let li = lastInsert, let raw = li.raw, let p = proxy() else { return }
        for _ in 0..<li.text.count { p.deleteBackward() }
        p.insertText(raw)
        lastInsert = nil
        lastBack = nil
        lastLang = nil
    }

    func type(_ s: String) {
        lastInsert = nil
        proxy()?.insertText(s)
    }

    func deleteOnce() {
        lastInsert = nil
        proxy()?.deleteBackward()
    }

    func startDeleteRepeat() {
        deleteOnce()
        deleteRepeat?.invalidate()
        deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    MainActor.assumeIsolated { self?.proxy()?.deleteBackward() }
                }
            }
        }
    }

    func stopDeleteRepeat() {
        deleteRepeat?.invalidate()
        deleteRepeat = nil
    }
}
