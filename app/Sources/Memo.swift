// Memo — 備忘錄：最近 20 句口述
//
// 為什麼要有：字沒貼進去、辨識不完整、潤飾失敗——這些情況下話不能白講。
// 每一句（含辨識不完整的）都留一份在這裡，狀態視窗看得到、點一下就複製。
// 只存在這台電腦（UserDefaults），不出機器。

import Foundation

struct MemoEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let at: Date
    /// 這句是不是真的貼進游標了（false＝只進了剪貼簿）
    let pasted: Bool

    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: at)
    }
}

final class Memo: ObservableObject {
    static let shared = Memo()
    private static let key = "memoEntries"
    static let limit = 20

    @Published private(set) var entries: [MemoEntry] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
            let list = try? JSONDecoder().decode([MemoEntry].self, from: d)
        {
            entries = list
        }
    }

    func add(_ text: String, pasted: Bool) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        DispatchQueue.main.async {
            self.entries.insert(MemoEntry(id: UUID(), text: t, at: Date(), pasted: pasted), at: 0)
            if self.entries.count > Self.limit { self.entries = Array(self.entries.prefix(Self.limit)) }
            self.persist()
        }
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }
}
