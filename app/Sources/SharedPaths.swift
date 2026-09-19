// SharedPaths — 檔案落點的唯一真相
//
// Talky 自己的資料夾＝~/Library/Application Support/Talky/
//
// ⚠ 唯一例外：同一台電腦如果已經裝過同一家的會議記錄 app（Hearby），它的資料夾裡已經有
//   ①同一顆 whisper 語音模型（1.5GB）②同一份常用詞（glossary.txt）。
//   讓使用者為了同樣的東西再下載一次 1.5GB、再打一次詞庫，是純粹的浪費，
//   所以這裡保留兩個「舊資料夾名」常數去借用。整個專案只有這個檔可以出現那個舊名字；
//   借不到就一切走 Talky 自己的路徑，沒有任何行為差異。
//   （clean 檢查腳本 scripts/check-clean.sh 把本檔列為白名單，就是為了這兩條。）

import AppKit
import Foundation

enum SharedPaths {
    /// Talky 自己的資料夾（模型、詞庫、下載暫存、中性工作目錄都在這）
    static var support: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talky")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// 例外①：同一家會議記錄 app 的資料夾名（借模型與詞庫用，不寫入）
    private static let siblingSupportFolderName = "WereHear"

    /// 例外③：同一家會議記錄 app 的 bundle id（精靈第 4 步用：它 1.1 之前也聽右 ⌘，兩邊會打架）
    private static let siblingBundleID = "ltd.intention.werehear"
    static var siblingAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == siblingBundleID }
    }
    /// 例外④：鄰居的輸入法開關（它的 imeMode 設定；它每次觸發都即時讀，關掉立刻生效、會議功能不受影響）
    static var siblingIMEEnabled: Bool {
        CFPreferencesAppSynchronize(siblingBundleID as CFString)
        return (CFPreferencesCopyAppValue("imeMode" as CFString, siblingBundleID as CFString) as? Bool) ?? false
    }
    @discardableResult
    static func disableSiblingIME() -> Bool {
        CFPreferencesSetAppValue("imeMode" as CFString, kCFBooleanFalse, siblingBundleID as CFString)
        let ok = CFPreferencesAppSynchronize(siblingBundleID as CFString)
        TalkyLog.write("sibling ime off: \(ok)")
        return ok
    }

    /// 例外②：借用來源的根目錄（不存在就是 nil，一切照常）
    static var siblingSupport: URL? {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(siblingSupportFolderName)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// 模型搜尋順序：先借鄰居的（已下載就不重下），再看自己的
    static func modelSearchPaths(_ file: String) -> [String] {
        var out: [String] = []
        if let s = siblingSupport { out.append(s.appendingPathComponent("models/\(file)").path) }
        out.append(support.appendingPathComponent("models/\(file)").path)
        return out
    }

    /// 常用詞檔：鄰居的存在就讀寫同一份（兩個 app 共用一份詞庫是刻意的），否則用自己的
    static var glossaryFile: URL {
        if let s = siblingSupport {
            let f = s.appendingPathComponent("glossary.txt")
            if FileManager.default.fileExists(atPath: f.path) { return f }
        }
        return support.appendingPathComponent("glossary.txt")
    }

    /// 新下載的模型一律落自己家（不寫進鄰居的資料夾）
    static func downloadDestination(_ file: String) -> URL {
        support.appendingPathComponent("models/\(file)")
    }

    /// 記錄檔資料夾
    static var logDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Talky", isDirectory: true)
    }
}
