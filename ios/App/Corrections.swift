// Corrections — 講話中途改口（「早上十點開會，啊不對，是下午兩點」）的處理
//
// 真機＋Mac 實測：本機小模型直接整理改口句時，常把「啊不對是下午兩點」整段刪掉、
// 留下錯的舊時間（Guards 會擋下、退原話，安全但沒整理）。叫它抽出新舊說法也不穩（整句照抄、新舊對調）。
// 所以拆成：①找出「舊說法、新說法」②程式替換 ③再交給一般整理。
//   ①先用規則：時間、金額、數字（新說法帶單位「點／元…」就往前找同單位的舊說法）——不靠模型
//   ①再用模型：人名、地名那類，模型抽出來後一定要過程式驗證（位置、長度、不在就對調或放棄）
// 任何一步沒把握就放棄＝維持原本行為（原話＋標點），不會改錯。

import Foundation
import FoundationModels

enum Corrections {
    /// 改口標記（跟 Guards.correctionMarks 同一組）
    static let marks = ["不對", "說錯了", "講錯了", "說錯", "講錯", "口誤", "我是說"]
    /// 標記前面可以出現的語氣字（「啊不對」「吧不對」）；前面是這些或標點才算改口（「他說不對」不算）
    static let leadIns: Set<Character> = ["啊", "阿", "喔", "哦", "欸", "誒", "呃", "嗯", "吧", "嘛", "啦", "呀", "，", ",", " ", "。"]
    /// 新說法到這裡為止
    static let stopWords = ["然後", "還有", "再來", "就好", "就行"]
    static let stopChars: Set<Character> = ["，", ",", "。", "、", "？", "！", "?", "!", " "]
    static let numerals: Set<Character> = Set("〇零一二三四五六七八九十百千萬兩0123456789:：")
    static let tails: Set<Character> = ["半", "多", "整"]
    static let units: Set<Character> = Set("點元塊號日天月年歲分秒位個人張台間週次樓")
    static let timePrefixes = ["早上", "上午", "中午", "下午", "晚上", "凌晨", "傍晚", "今天", "明天", "後天", "昨天"]

    /// 有改口就回傳改好的逐字稿；沒把握回 nil
    static func resolve(_ raw: String) async -> String? {
        guard let m = lastMark(raw) else { return nil }
        if let pair = byUnit(raw, m), let fixed = apply(raw, m, old: pair.old, new: pair.new) { return fixed }
        if let pair = await byModel(raw), let fixed = apply(raw, m, old: pair.old, new: pair.new) { return fixed }
        return nil
    }

    // MARK: 找標記

    /// 最後一個「像改口」的標記位置（Character 陣列索引：[start, end)）
    static func lastMark(_ raw: String) -> (start: Int, end: Int)? {
        let chars = Array(raw)
        var best: (Int, Int)?
        for mk in marks {
            let mc = Array(mk)
            guard chars.count >= mc.count else { continue }
            var i = chars.count - mc.count
            while i >= 0 {
                if Array(chars[i..<i + mc.count]) == mc {
                    // 前面要是語氣字、標點、句首，或剛講完的數字／單位（「五百元不對」），才算改口；「他說不對」不算
                    if i == 0 || leadIns.contains(chars[i - 1]) || numerals.contains(chars[i - 1])
                        || units.contains(chars[i - 1]) || tails.contains(chars[i - 1])
                    {
                        if best == nil || i > best!.0 { best = (i, i + mc.count) }
                    }
                    break
                }
                i -= 1
            }
        }
        return best
    }

    // MARK: 規則：時間、金額、數字

    static func byUnit(_ raw: String, _ m: (start: Int, end: Int)) -> (old: String, new: String)? {
        let chars = Array(raw)
        // 新說法：標記後面（略過「是」與標點），到停止點為止
        var i = m.end
        while i < chars.count, [" ", "，", ",", "是"].contains(chars[i]) { i += 1 }
        var newChars: [Character] = []
        while i < chars.count, newChars.count < 10, !stopChars.contains(chars[i]) {
            if stopWords.contains(where: { w in Array(w) == Array(chars[i..<min(chars.count, i + w.count)]) }) { break }
            newChars.append(chars[i])
            i += 1
        }
        // 新說法截到單位（與後面的「半／多／分」）為止：「下午兩點給你」→「下午兩點」；純數字截到數字結束
        if let u = newChars.lastIndex(where: { units.contains($0) }) {
            var e = u
            while e + 1 < newChars.count, numerals.contains(newChars[e + 1]) || tails.contains(newChars[e + 1]) || newChars[e + 1] == "分" {
                e += 1
            }
            newChars = Array(newChars[...e])
        } else if let n = newChars.lastIndex(where: { numerals.contains($0) }) {
            newChars = Array(newChars[...n])
        }
        let new = String(newChars)
        guard new.contains(where: { numerals.contains($0) }) else { return nil }

        let before = Array(chars[..<m.start])
        // 舊說法：往前找同一個單位字（新說法以「點」「元」…結尾）；新說法是純數字就找最近一段數字
        let unit = newChars.last(where: { units.contains($0) })
        var j = before.count - 1
        if let unit {
            while j >= 0, before[j] != unit { j -= 1 }
            // 「10:00 開會，啊不對是下午兩點」：往前沒有「點」就找時:分
            if j < 0, unit == "點", var t = lastClock(String(before)) {
                // 新說法沒講「下午」這類字，舊的「早上」就留在原處（只換時間本身）
                if !timePrefixes.contains(where: { new.hasPrefix($0) }) {
                    for p in timePrefixes where t.hasPrefix(p) { t = String(t.dropFirst(p.count)) }
                    t = t.trimmingCharacters(in: .whitespaces)
                }
                return (t, new)
            }
        } else {
            while j >= 0, !numerals.contains(before[j]) { j -= 1 }
        }
        guard j >= 0, m.start - j <= 14 else { return nil }
        // 舊說法的尾巴：單位後面緊接的「半／多／分」與數字（「七點半」）
        var end = j
        while end + 1 < before.count, numerals.contains(before[end + 1]) || tails.contains(before[end + 1]) || before[end + 1] == "分" {
            end += 1
        }
        // 往前吃數字
        var k = unit != nil ? j - 1 : j
        while k >= 0, numerals.contains(before[k]) { k -= 1 }
        let numStart = k + 1
        guard numStart <= (unit != nil ? j - 1 : j) else { return nil }  // 至少一個數字
        var start = numStart
        // 新說法有講「下午」這類字，舊說法才連前面的「早上」一起換（「下午三點…不對是四點」→ 只換成「下午四點」）
        for p in timePrefixes where timePrefixes.contains(where: { new.hasPrefix($0) }) {
            let pc = Array(p)
            if start >= pc.count, Array(before[start - pc.count..<start]) == pc {
                start -= pc.count
                break
            }
        }
        let old = String(before[start...end])
        return old == new ? nil : (old, new)
    }

    /// 最後一個「(早上)10:00」型的時間
    static func lastClock(_ s: String) -> String? {
        let pattern = "(早上|上午|中午|下午|晚上|凌晨|傍晚)?\\s*\\d{1,2}[:：]\\d{2}"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let last = re.matches(in: s, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return ns.substring(with: last.range)
    }

    // MARK: 模型：人名、地名

    @Generable
    struct Pair {
        @Guide(description: "被推翻的舊說法：改口之前說錯的那幾個字，照抄原字")
        var old: String
        @Guide(description: "改口後的新說法：改口標記後面、用來取代 old 的那幾個字，照抄原字")
        var new: String
    }

    static let instructions = """
        逐字稿裡說話者講錯後當場改口（例如「啊不對」「不是…是…」「說錯了」「我是說」）。
        找出兩段字，都要照抄逐字稿原本的字，不要改寫、不要補字：
        - old：被推翻的舊說法（改口之前說錯的那幾個字）
        - new：改口後的新說法（改口標記後面、用來取代 old 的那幾個字）
        old 和 new 通常是同一類東西：時間換時間、數字換數字、人名換人名、地點換地點。
        """
    static let shots: [(String, String, String)] = [
        ("我們明天下午三點要開會嘛啊不對是四點", "三點", "四點"),
        ("報價單明天早上十點給你啊不對是下午兩點給你", "早上十點", "下午兩點"),
        ("我等一下打給小明，不對，是小華", "小明", "小華"),
        ("這個寄到桃園啊說錯了寄到新竹", "桃園", "新竹"),
    ]

    static func byModel(_ raw: String) async -> (old: String, new: String)? {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard model.isAvailable else { return nil }
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(.init(content: instructions))], toolDefinitions: []))
        ]
        for (u, o, n) in shots {
            guard let data = try? JSONSerialization.data(withJSONObject: ["old": o, "new": n]),
                let json = String(data: data, encoding: .utf8), let content = try? GeneratedContent(json: json)
            else { continue }
            entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: "〈逐字稿〉\(u)〈/逐字稿〉"))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.structure(.init(source: "Pair", content: content))])))
        }
        let transcript = Transcript(entries: entries)
        let pair = await withTimeout(4) {
            let s = LanguageModelSession(model: model, tools: [], transcript: transcript)
            let r = try await s.respond(
                to: "〈逐字稿〉\(raw)〈/逐字稿〉", generating: Pair.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 80))
            return [r.content.old, r.content.new]
        }
        guard let p = pair, p.count == 2 else { return nil }
        let old = trimOld(p[0])
        let new = trimNew(p[1])
        // 人名地名那類：兩邊都短、長度相近（「他說」換成「我們明天再談」這種一律不收）
        guard (1...8).contains(old.count), (1...8).contains(new.count), abs(old.count - new.count) <= 2 else { return nil }
        return (old, new)
    }

    static func trimNew(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.firstIndex(where: { stopChars.contains($0) }) { t = String(t[..<r]) }
        for w in stopWords { if let r = t.range(of: w) { t = String(t[..<r.lowerBound]) } }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func trimOld(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.lastIndex(where: { stopChars.contains($0) }) { t = String(t[t.index(after: r)...]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: 替換

    /// 刪掉「語氣字＋標記＋新說法（＋重複的尾巴）」，再把標記前最後一個舊說法換成新說法。
    /// 舊說法必須在標記前、新說法在標記後；顛倒就對調一次，還不對就放棄。
    static func apply(_ raw: String, _ m: (start: Int, end: Int), old: String, new: String) -> String? {
        let chars = Array(raw)
        let before = String(chars[..<m.start])
        let after = String(chars[m.end...])
        var o = old, n = new
        if !(before.contains(o) && after.contains(n)) {
            guard before.contains(n), after.contains(o) else { return nil }
            swap(&o, &n)
        }
        guard !o.isEmpty, !n.isEmpty, o != n else { return nil }
        let oc = Array(o), nc = Array(n)

        // 標記前最後一個舊說法的位置
        var oldAt = -1
        var i = m.start - oc.count
        while i >= 0 {
            if Array(chars[i..<i + oc.count]) == oc { oldAt = i; break }
            i -= 1
        }
        guard oldAt >= 0 else { return nil }
        let oldEnd = oldAt + oc.count

        // 要刪的那段：從標記前的語氣字開始
        var cutStart = m.start
        while cutStart > oldEnd, leadIns.contains(chars[cutStart - 1]) { cutStart -= 1 }
        // 到新說法結束
        var j = m.end
        var newAt = -1
        while j + nc.count <= chars.count {
            if Array(chars[j..<j + nc.count]) == nc { newAt = j; break }
            j += 1
        }
        guard newAt >= 0, newAt - m.end <= 4 else { return nil }  // 新說法要緊接在標記後
        var cutEnd = newAt + nc.count
        // 「十點給你啊不對是兩點給你」：新說法後面重複了舊說法後面那段，一起刪
        let tail = Array(chars[oldEnd..<cutStart])
        if !tail.isEmpty, cutEnd + tail.count <= chars.count, Array(chars[cutEnd..<cutEnd + tail.count]) == tail {
            cutEnd += tail.count
        }
        var out = Array(chars[..<cutStart]) + Array(chars[cutEnd...])
        out.replaceSubrange(oldAt..<oldEnd, with: nc)
        return String(out)
    }
}
