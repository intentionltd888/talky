// Settings — 設定、金鑰、備忘錄
//
// 設定放 App Group（鍵盤也讀得到）；備忘錄＝最近 20 句，字沒貼進去時話不會白講，只存在這支手機。
// Claude 整理走自己的訂閱：請配對的 Mac 或自架的整理服務代跑，手機這邊沒有任何金鑰。

import Foundation

enum PolishMode: String, CaseIterable, Identifiable {
    /// Apple：iOS 27 起先走 Apple 私有雲模型，不行再退手機本機模型
    case apple
    /// 自己的 Claude 訂閱：請配對的 Mac（或自架的整理服務）上登入的 Claude Code 代跑，不用 API 金鑰
    case claude
    /// 不整理：只做繁體化與標點
    case off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple"
        case .claude: return "訂閱"
        case .off: return "不整理"
        }
    }
}

enum Settings {
    private static var d: UserDefaults { Bridge.shared }

    static var polishMode: PolishMode {
        get { PolishMode(rawValue: d.string(forKey: "polishMode") ?? "") ?? .apple }
        set { d.set(newValue.rawValue, forKey: "polishMode") }
    }
    /// 配對的 Mac 要用哪一顆：""＝照 Mac 自己的設定、claude＝Claude Code、codex＝ChatGPT 的 Codex
    static var macBrain: String {
        get { d.string(forKey: "macBrain") ?? "" }
        set { d.set(newValue, forKey: "macBrain") }
    }
    /// 可選：claude-opus-5-5（預設；實測整理一句 1.8 秒）／claude-sonnet-5／claude-haiku-4-5-20251001
    static let claudeModels = ["claude-opus-5-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
    static var claudeModel: String {
        get {
            let m = d.string(forKey: "claudeModel") ?? ""
            return claudeModels.contains(m) ? m : claudeModels[0]
        }
        set { d.set(newValue, forKey: "claudeModel") }
    }
    /// 自架的整理服務位址（選用）。公開原始碼裡是空的：要用就把位址寫在 ~/.config/talky/ios-bridge-url（一行，不進倉），
    /// ios/install.sh 編譯時帶進 Info.plist 的 TalkyBridgeURL
    static let defaultBridgeURL =
        (Bundle.main.object(forInfoDictionaryKey: "TalkyBridgeURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    static var bridgeURL: String {
        get { d.string(forKey: "bridgeURL") ?? defaultBridgeURL }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bridgeURL") }
    }
    /// Apple 私有雲模型（iOS 27+）；關掉就只用手機本機模型
    static var usePCC: Bool {
        get { d.object(forKey: "usePCC") as? Bool ?? true }
        set { d.set(newValue, forKey: "usePCC") }
    }
    /// 待命幾分鐘（最後一次講完起算）；0＝不關（直到按「結束待命」）。
    /// 預設不關（目的：不用跳轉畫面，在原地就能直接啟用）：跳一次 app 之後整天都在原地講
    static var keepAliveMinutes: Int {
        get { d.object(forKey: "keepAliveMinutes") as? Int ?? 0 }
        set { d.set(newValue, forKey: "keepAliveMinutes") }
    }
    static var keepAliveLabel: String { keepAliveMinutes == 0 ? "不關" : "\(keepAliveMinutes) 分鐘" }
    /// 常用詞（人名／公司名／專有名詞）：辨識與整理都會用
    static var glossary: String {
        get { d.string(forKey: "glossary") ?? "" }
        set { d.set(newValue, forKey: "glossary") }
    }
    static var glossaryTerms: [String] { TextRules.terms(glossary) }

}

struct MemoEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let raw: String
    let path: String
    let at: Date
    /// 翻譯的話是哪種語言（en／ja／th）；舊資料沒有這欄＝中文
    var lang: String? = nil

    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: at)
    }
}

@MainActor
final class Memo: ObservableObject {
    static let shared = Memo()
    private static let key = "memoEntries"
    static let limit = 20

    @Published private(set) var entries: [MemoEntry] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
            let list = try? JSONDecoder().decode([MemoEntry].self, from: data)
        {
            entries = list
        }
    }

    func add(text: String, raw: String, path: String, lang: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        entries.insert(MemoEntry(id: UUID(), text: t, raw: raw, path: path, at: Date(), lang: lang), at: 0)
        if entries.count > Self.limit { entries = Array(entries.prefix(Self.limit)) }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
