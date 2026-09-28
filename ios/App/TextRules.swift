// TextRules — 口述文字的確定性處理層（不靠 AI 的那一半）
//
// 從 Mac 版 TextUtil.swift 原樣移植：簡轉繁、標點全形、幻聽句過濾。
// 整理（AI）失敗時，口述照樣走完這一層再貼出去——字是對的，只是不修語氣。

import Foundation

enum TextRules {
    /// 產出絕不出現簡體字：ICU 詞典級轉換（干净→乾淨、头发→頭髮、皇后不動）
    static func toTraditional(_ s: String) -> String {
        s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    }

    /// 半形標點轉全形。保守：前一字是中文才換；句點另需後一字也是中文／空白／行尾（不傷 3.5、v2.0、網址）
    static func normalizePunct(_ s: String) -> String {
        let map: [Character: Character] = [",": "，", "!": "！", "?": "？", ";": "；", ":": "："]
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

    static func isCJK(_ c: Character?) -> Bool {
        guard let c, let u = c.unicodeScalars.first else { return false }
        return isCJK(u)
    }
    static func isCJK(_ u: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(Int(u.value)) }

    /// 「只加標點的原話」：AI 整理失敗或關掉時的出口
    static func light(_ raw: String) -> String {
        finalize(normalizePunct(toTraditional(raw)))
    }

    // ── 辨識結果的機械修正（進整理之前）──
    //
    // 真機實測：Apple 的 zh-TW 辨識偶爾吐錯的繁體字形（復雜）、把「啊不對」聽成「阿佈對」。
    // 只收「錯了一定是錯」的組合（佈對不是詞、復雜在台灣用字一定是複雜），不收有歧義的。
    static let asrFixes: [(String, String)] = [
        ("佈對", "不對"),
        ("復雜", "複雜"), ("復製", "複製"), ("重復", "重複"),
    ]

    static func fixASR(_ s: String) -> String {
        var t = s
        for (bad, good) in asrFixes where t.contains(bad) { t = t.replacingOccurrences(of: bad, with: good) }
        return t
    }

    // ── 最後一道排版（整理完、打進去之前）──
    //
    // 中文與英文字母／數字之間空一格（「feature 下禮拜」「PM 確認」「10:00 開會」），
    // 全形標點前面不留空格（辨識常吐「複雜了 ，」）。只加空白、不改任何字。
    static func finalize(_ s: String) -> String {
        let fullPunct: Set<Character> = ["，", "。", "？", "！", "、", "；", "：", "」", "）"]
        let chars = Array(s)
        var out: [Character] = []
        out.reserveCapacity(chars.count + 8)
        for (i, c) in chars.enumerated() {
            // 全形標點前的空白拿掉
            if c == " ", i + 1 < chars.count, fullPunct.contains(chars[i + 1]) { continue }
            if let prev = out.last, needsSpace(prev, c) { out.append(" ") }
            out.append(c)
        }
        return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLatinOrDigit(_ c: Character) -> Bool {
        guard let u = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return u.isASCII && (CharacterSet.letters.contains(u) || CharacterSet.decimalDigits.contains(u))
    }

    private static func needsSpace(_ a: Character, _ b: Character) -> Bool {
        (isCJK(a) && isLatinOrDigit(b)) || (isLatinOrDigit(a) && isCJK(b))
    }

    // ── 幻聽過濾（語音模型對靜音偶爾吐字幕片尾詞）──

    static let strongJunkPatterns = [
        "謝謝觀看", "謝謝收看", "字幕由", "Amara", "amara.org", "字幕提供", "中文字幕", "字幕志願者",
        "感謝觀看", "感謝收看", "請不吝", "點贊", "打賞", "欄目", "♪", "🎵", "(音樂)", "[音樂]",
        "以上言論不代表本台立場", "感謝您的觀看", "感謝您的收看",
    ]
    static let exactJunk: Set<String> = ["thank you.", "thank you", "thanks for watching.", "you"]

    static func isHallucination(_ text: String) -> Bool {
        if text.isEmpty { return true }
        let bare = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " 。．，,!！?？"))
        if bare.isEmpty || exactJunk.contains(bare) { return true }
        var stripped = text
        var hit = false
        for junk in strongJunkPatterns where stripped.contains(junk) {
            hit = true
            stripped = stripped.replacingOccurrences(of: junk, with: "")
        }
        if hit {
            let residue = stripped.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || isCJK($0)
            }.count
            if residue < 4 { return true }
        }
        return false
    }

    /// 常用詞字串 → 詞表（、，, 換行都算分隔）
    static func terms(_ glossary: String) -> [String] {
        let seps: Set<Character> = ["、", ",", "，", "\n"]
        var seen = Set<String>()
        return glossary.split(whereSeparator: { seps.contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
