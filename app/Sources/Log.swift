// Log — app 記錄檔（出問題時唯一的診斷輸入）
// 位置：~/Library/Logs/Talky/talky.log；滿 1MB 輪替，最多留 5 份（舊份進垃圾桶，不硬刪）

import Foundation

enum TalkyLog {
    static var dir: URL { SharedPaths.logDir }
    static var file: URL { dir.appendingPathComponent("talky.log") }
    private static let q = DispatchQueue(label: "ltd.intention.talky.log")
    private static let maxBytes = 1_000_000
    private static let keep = 5

    static func write(_ line: String) {
        q.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let entry = "[\(f.string(from: Date()))] \(line)\n"
            rotateIfNeeded()
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile()
                h.write(Data(entry.utf8))
                try? h.close()
            } else {
                try? Data(entry.utf8).write(to: file)
            }
        }
    }

    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
            let size = attrs[.size] as? Int, size > maxBytes
        else { return }
        for i in stride(from: keep - 1, through: 1, by: -1) {
            let src = dir.appendingPathComponent("talky.\(i).log")
            let dst = dir.appendingPathComponent("talky.\(i + 1).log")
            if FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.trashItem(at: dst, resultingItemURL: nil)
            }
            try? FileManager.default.moveItem(at: src, to: dst)
        }
        try? FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("talky.1.log"))
    }

    /// 最近 N 行（診斷畫面用）
    static func tail(_ n: Int = 200) -> String {
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        return s.components(separatedBy: "\n").suffix(n).joined(separator: "\n")
    }
}

struct TalkyError: LocalizedError {
    let msg: String
    init(_ m: String) { msg = m }
    var errorDescription: String? { msg }
}
