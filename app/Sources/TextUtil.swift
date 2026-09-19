// TextUtil — 口述文字的確定性處理層（不靠 AI 的那一半）
//
// 這裡的每一支都是「機械規則」：簡轉繁、標點全形、幻聽句過濾、常用詞。
// 潤飾（AI）失敗時，口述照樣走完這一層再貼出去——字是對的，只是不修語氣。

import Foundation

enum TextUtil {
    // ── 路徑與環境 ────────────────────────────────────────────

    /// 語音模型檔名（下載器與引擎共用）
    static var whisperModelFile: String { ModelCatalog.whisper.file }

    /// 語音模型實體路徑（借鄰居的優先，見 SharedPaths）
    static func whisperModelPath() -> String? {
        SharedPaths.modelSearchPaths(whisperModelFile)
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// 效能核心數（P-cores）＝CPU 轉寫執行緒數。whisper 預設 4——M 系列多核機等於一半算力閒置。
    static let perfCores: Int = {
        var n: Int32 = 0
        var sz = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.physicalcpu", &n, &sz, nil, 0)
        return n > 0 ? Int(n) : max(4, ProcessInfo.processInfo.activeProcessorCount / 2)
    }()

    /// 「這段錄音根本沒聲音」的音量門檻（0–1）
    static let silenceThreshold: Float = 0.015

    // ── 簡轉繁 ───────────────────────────────────────────────

    /// 產出絕不出現簡體字。macOS 內建 ICU 詞典級轉換——干净→乾淨、头发→頭髮、
    /// 皇后不動、后台不會變臺；辨識或潤飾偶發吐簡體都會被機械改回，不靠 prompt 求它。
    static func toTraditional(_ s: String) -> String {
        s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    }

    // ── 標點全形化 ────────────────────────────────────────────

    /// 語音辨識的中文輸出常帶半形標點。保守規則：前一字元是中文才替換（, ! ? ; :）；
    /// 句點另需後一字元也是中文／空白／行尾，避免誤傷 3.5、v2.0、網址與英文句子。
    static func normalizePunct(_ s: String) -> String {
        let map: [Character: Character] = [",": "，", "!": "！", "?": "？", ";": "；", ":": "："]
        func isCJK(_ c: Character?) -> Bool {
            guard let c, let u = c.unicodeScalars.first else { return false }
            return (0x4E00...0x9FFF).contains(Int(u.value))
        }
        let chars = Array(s)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        for (i, c) in chars.enumerated() {
            let prev = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if let rep = map[c], isCJK(prev) {
                out.append(rep)
            } else if c == ".", isCJK(prev), next == nil || next == " " || isCJK(next) {
                out.append("。")
            } else {
                out.append(c)
            }
        }
        return String(out)
    }

    // ── 幻聽過濾 ─────────────────────────────────────────────
    //
    // 語音模型對「靜音」會很有自信地吐出字幕片尾詞（謝謝觀看、請訂閱…）。
    // 三層：強片語剝除後看殘字、弱片語看佔比、整句白名單逐字命中。

    /// 強片語＝幻聽專屬句型（真人講話幾乎不可能出現的字幕聲明／片尾詞）
    static let strongJunkPatterns = [
        "謝謝觀看", "謝謝收看", "字幕由", "Amara", "amara.org", "字幕提供", "中文字幕",
        "字幕志願者", "志願者", "感謝觀看", "感謝收看", "請不吝", "點贊", "轉發", "打賞", "欄目", "點點欄目",
        "♪", "🎵", "(音樂)", "[音樂]",
        "已進行編輯", "以加入正確的標點符號", "以加入正確的標點", "編輯成功後",
        "以上言論不代表本台立場", "影片即將結束", "影片即將開始", "感謝您的觀看", "感謝您的收看",
        "這是一條語音備忘錄", "轉發打賞", "打賞支持", "分享出去並按一個讚",
    ]
    /// 弱片語＝真話裡也會出現的短詞，只在「佔整句一半以上」才判幻聽
    static let weakJunkPatterns = ["請訂閱", "訂閱", "點贊"]
    /// 整句幻聽白名單（靜音時的固定產物，去頭尾標點後逐字命中即丟）
    static let exactJunk: Set<String> = [
        "thank you.", "thank you", "thanks for watching.", "thanks for watching", "you",
    ]

    static func isHallucination(_ text: String) -> Bool {
        if text.isEmpty { return true }
        let bare = text.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " 。．，,!！?？"))
        if exactJunk.contains(bare) { return true }
        var stripped = text
        var strongHit = false
        for junk in strongJunkPatterns where stripped.contains(junk) {
            strongHit = true
            stripped = stripped.replacingOccurrences(of: junk, with: "")
        }
        if strongHit {
            let residue = stripped.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || (0x4E00...0x9FFF).contains(Int($0.value))
            }.count
            if residue < 4 { return true }
        }
        return weakJunkPatterns.contains { junk in
            text.contains(junk) && junk.count * 2 >= text.count
        }
    }

    // ── 常用詞（glossary.txt）──────────────────────────────────

    /// 這台電腦自己的常用詞（人名／公司名／專有名詞），不寫死在程式裡。
    /// 檔案位置見 SharedPaths.glossaryFile（同一台裝了會議記錄 app 就共用同一份）。
    static func localGlossary() -> String? {
        guard let s = try? String(contentsOf: SharedPaths.glossaryFile, encoding: .utf8) else {
            return nil
        }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 進辨識引擎 initial prompt 的常用詞（**字數**上限版）。
    /// 上限卡的是模型的 prompt 長度（約 224 token）：塞太多會讓整段辨識崩壞成同一句幻聽。
    /// 120 字 ≈ 110–140 token，離上限仍有餘裕。挑法＝檔尾優先（越後面越新＝最近加的最相關）。
    static let whisperGlossaryMaxChars = 120
    static func whisperGlossary(maxChars: Int = whisperGlossaryMaxChars) -> String? {
        guard maxChars > 0, let g = localGlossary() else { return nil }
        let seps: Set<Character> = ["、", ",", "，", "\n"]
        let terms = g.split(whereSeparator: { seps.contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var picked: [String] = []
        var used = 0
        for t in terms.reversed() where !picked.contains(t) {
            let cost = t.count + 1
            if used + cost > maxChars { continue }  // 裝不下就跳過繼續找，不是整份放棄
            picked.append(t)
            used += cost
        }
        return picked.isEmpty ? nil : picked.joined(separator: "、")
    }

    /// 寫回常用詞（設定頁編輯用）。additive：呼叫端給的是完整內容，這裡只負責落檔。
    @discardableResult
    static func writeGlossary(_ text: String) -> Bool {
        let url = SharedPaths.glossaryFile
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            TalkyLog.write("glossary write fail: \(error.localizedDescription)")
            return false
        }
    }
}
