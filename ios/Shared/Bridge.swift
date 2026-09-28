// Bridge — 主 app 與鍵盤之間的傳話層（App Group＋Darwin 通知）
//
// 為什麼要有：iOS 的鍵盤擴充不能開麥克風。收音、辨識、整理一律在主 app 做，
// 鍵盤只負責「開始／停止」與「把整理好的字打進游標」。兩邊靠這裡溝通：
// ・指令（鍵盤→app）：Darwin 通知 start／stop／cancel／ping／consumed
// ・狀態（app→鍵盤）：App Group 裡一份 state.json（原子寫入）＋ Darwin 通知 state 叫對方來讀
// Darwin 通知不帶資料，所以資料一律走檔案；鍵盤那邊另外輪詢一次當保險。

import Foundation

enum Bridge {
    static let appGroup = "group.ltd.intention.talky"
    /// 鍵盤叫醒主 app 開始收音
    static let listenURL = URL(string: "talky://listen")!

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
    /// 兩邊都讀得到的設定（鍵盤沒開「完整取用」時讀不到，呼叫端要能接受預設值）
    static let shared: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    enum Signal: String, CaseIterable {
        case start = "ltd.intention.talky.start"
        case stop = "ltd.intention.talky.stop"
        case cancel = "ltd.intention.talky.cancel"
        case ping = "ltd.intention.talky.ping"
        case pong = "ltd.intention.talky.pong"
        case state = "ltd.intention.talky.state"
        case consumed = "ltd.intention.talky.consumed"
    }

    static func post(_ s: Signal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(s.rawValue as CFString), nil, nil,
            true)
    }

    // ── 事件記錄：App Group 的 Library/talky-events.log（app 與鍵盤共用）──
    // 只記步驟、狀態、字數與秒數，**不記講的內容**；開發時用 devicectl 抓來看整條流程卡在哪。
    private static let logQueue = DispatchQueue(label: "ltd.intention.talky.log")
    private static let logTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    static var libraryDir: URL? { container?.appendingPathComponent("Library", isDirectory: true) }

    static func log(_ who: String, _ msg: String) {
        guard let dir = libraryDir else { return }
        let line = "\(logTime.string(from: Date())) [\(who)] \(msg)\n"
        logQueue.async {
            let url = dir.appendingPathComponent("talky-events.log")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                let size = h.offsetInFile
                try? h.close()
                // 超過 256KB 只留後半
                if size > 256 * 1024, let d = try? Data(contentsOf: url) {
                    try? d.suffix(128 * 1024).write(to: url, options: .atomic)
                }
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }

    /// 鍵盤已經打進游標的那一句（跨鍵盤實例共用，避免同一句被貼兩次）
    static var consumedResultID: String? {
        get { shared.string(forKey: "consumedResultID") }
        set { shared.set(newValue, forKey: "consumedResultID") }
    }
}

/// Darwin 通知的接收端。C 回呼不能抓 closure，靠這個物件轉手；物件消失就自動退訂。
final class SignalListener {
    private var handlers: [String: () -> Void] = [:]

    func on(_ s: Bridge.Signal, _ handler: @escaping () -> Void) {
        handlers[s.rawValue] = handler
        let me = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), me,
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let listener = Unmanaged<SignalListener>.fromOpaque(observer).takeUnretainedValue()
                let key = name.rawValue as String
                DispatchQueue.main.async { listener.handlers[key]?() }
            }, s.rawValue as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}

/// app 寫、鍵盤讀的即時狀態（state.json）
struct LiveState: Codable, Equatable {
    enum Phase: String, Codable {
        /// 沒在待命（麥克風關著；鍵盤按下去要先叫醒 app）
        case off
        /// 待命中：麥克風開著但不收，按了就聽
        case ready
        case listening
        /// 辨識收尾＋整理中
        case working
        /// 有一句整理好了，等鍵盤貼
        case done
        case failed
    }
    /// 這句是誰要的：鍵盤要的才會自動貼；app 裡「試講一句」的不貼
    enum Target: String, Codable { case keyboard, app }

    var phase: Phase = .off
    var target: Target = .keyboard
    /// 待命到幾點（只是提示；app 是否真的活著，鍵盤以 ping／pong 為準）
    var readyUntil: Date?
    var partial: String = ""
    var level: Float = 0
    var resultID: String?
    var result: String?
    var raw: String?
    /// 整理走哪條：pcc／apple／claude／light；翻譯：claude／apple-tr
    var path: String?
    /// 這一句要翻成什麼（th:girl 這種；nil＝中文）：聽的當下就寫，鍵盤與動態島顯示「翻成泰文・女生朋友」
    var out: String?
    /// 翻譯才有：譯成哪種語言（en／ja／th）、譯文直譯回中文（鍵盤顯示「意思：…」）
    var lang: String?
    var back: String?
    /// true＝翻譯沒成功、只有中文：鍵盤不要自動打，讓人自己按
    var hold: Bool?
    var message: String?
    var stamp: Date = Date()

    /// 放在 Library/ 底下：開發工具（devicectl）只讀得到容器的 Library／Documents／tmp
    static var url: URL? { Bridge.libraryDir?.appendingPathComponent("state.json") }

    static func load() -> LiveState {
        guard let url, let d = try? Data(contentsOf: url),
            let s = try? JSONDecoder().decode(LiveState.self, from: d)
        else { return LiveState() }
        return s
    }

    func save() {
        guard let url = Self.url, let d = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: url, options: .atomic)
    }

    var sessionAlive: Bool {
        phase != .off && (readyUntil ?? .distantPast) > Date()
    }
}
