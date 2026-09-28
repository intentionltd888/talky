// Translate — 翻譯：講中文，打出「對方的語言＋對方關係該有的語氣」
//
// 用法照 Typeless（設定的邏輯也一樣）：
// ・設定裡排好「翻譯目標」（最多 4 個）；Talky 多做一步：每個目標＝語言＋對象（泰文・女生朋友、日文・客戶…）
// ・鍵盤：點一下圓鈕＝講中文；長按圓鈕往上滑到某個目標、放開＝這一句翻成它。每一句現場挑，不會卡在翻譯模式
//   （不會忘了切回來，把泰文傳給台灣客戶）
// 鍵盤把「這一句要翻成什麼」寫進 App Group（nextOutput）再叫 app 開始聽；app 開始聽的那一刻取走。
// 每個對象的 guide 原文送給 Claude，只管「語氣與稱呼對方」；句尾（ครับ／ค่ะ）與有性別的自稱只看「口吻」那一條
// （兩條規則都管句尾會打架，模型聽後面那條）。各語言的共通落差規則在整理服務那邊（配對的 Mac 或自架服務），跟 Mac 版同一份。

import Foundation

enum OutputLang: String, CaseIterable, Identifiable {
    case zh, en, ja, th
    var id: String { rawValue }

    var label: String {
        switch self {
        case .zh: return "中文"
        case .en: return "英文"
        case .ja: return "日文"
        case .th: return "泰文"
        }
    }
    /// 翻好的字要是這種文字才算數（防模型回錯語言）
    func looksRight(_ s: String) -> Bool {
        let us = s.unicodeScalars
        switch self {
        case .zh: return true
        case .en: return us.contains { $0.isASCII && CharacterSet.letters.contains($0) }
        case .ja: return us.contains { (0x3040...0x30FF).contains($0.value) }  // 平假名／片假名
        case .th: return us.contains { (0x0E00...0x0E7F).contains($0.value) }
        }
    }
    /// Apple 翻譯（離線備援）用的語言代碼
    var appleCode: String {
        switch self {
        case .zh: return "zh-Hant"
        case .en: return "en"
        case .ja: return "ja"
        case .th: return "th"
        }
    }
}

/// 說話者口吻：泰文的 ครับ／ค่ะ、ผม／ฉัน，日文口語的 僕／私 都看這個（不猜，使用者自己選）
enum SpeakerVoice: String, CaseIterable, Identifiable {
    case unset, male, female
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unset: return "不指定"
        case .male: return "男生口吻"
        case .female: return "女生口吻"
        }
    }
}

struct Situation: Identifiable, Hashable {
    let id: String
    /// 鍵盤上的字（兩到四個字）
    let label: String
    /// 選它時鍵盤顯示的一句說明（給人看）
    let hint: String
    /// 送給 Claude 的情境說明（決定語氣）
    let guide: String
}

enum Translate {
    // MARK: 對象清單（每種語言四個，鍵盤一排放得下）

    static func situations(_ lang: OutputLang) -> [Situation] {
        switch lang {
        case .zh: return []
        case .en: return en
        case .ja: return ja
        case .th: return th
        }
    }

    static let en: [Situation] = [
        Situation(
            id: "client", label: "客戶", hint: "專業有禮、句子完整，不用俚語",
            guide:
                "對象是客戶或合作廠商。用專業、有禮、簡潔的商務英文：完整句子，不用俚語與口語縮寫（gonna、wanna、lol）；請求用 Could you…／Would it be possible to…／I'd appreciate…；感謝用 Thank you for…。不要自己加 Dear、Best regards 這類開頭結尾。"
        ),
        Situation(
            id: "colleague", label: "同事", hint: "像 Slack 訊息：友善直接、不拘謹",
            guide: "對象是同事或熟的合作夥伴，像 Slack 訊息。友善、直接、專業但不拘謹：可以用 I'll、let's 這類縮寫，句子短；不要太正式，也不要俚語。"
        ),
        Situation(
            id: "friend", label: "朋友", hint: "自然口語，像傳 LINE 給朋友",
            guide: "對象是朋友，像 WhatsApp／LINE 聊天。自然口語、輕鬆：用縮寫，可以用 hey、yeah、gonna 這類母語者常用的說法；不要書面腔。"
        ),
        Situation(
            id: "close", label: "親密", hint: "另一半、曖昧對象：溫暖親暱",
            guide: "對象是另一半或曖昧中的人。溫暖、親暱、自然，像傳給喜歡的人的訊息；原話有的甜要表達出來，但不要自己加情話或暱稱。"
        ),
    ]

    static let ja: [Situation] = [
        Situation(
            id: "client", label: "客戶", hint: "商務敬語：いただけますでしょうか、承知いたしました",
            guide:
                "對象是日本客戶。用標準商務敬語（丁寧語＋尊敬語／謙讓語）：〜いただけますでしょうか、恐れ入りますが、承知いたしました、ご確認のほどよろしくお願いいたします；對方公司稱「御社」（書面信件稱「貴社」），我方稱「弊社」。不要二重敬語、不要冗長。原話有問候時用「お世話になっております」。"
        ),
        Situation(
            id: "colleague", label: "同事", hint: "です・ます，職場常用語",
            guide: "對象是同事或熟的合作夥伴。用です・ます的丁寧語，友善簡潔；可用「了解です」「〜お願いします」這類職場常用語；原話有打招呼時用「お疲れさまです」。"
        ),
        Situation(
            id: "friend", label: "朋友", hint: "タメ口，〜ね、〜よ，不用敬語",
            guide: "對象是日本朋友。用タメ口（普通形）自然口語：語尾用〜ね、〜よ、〜じゃん、〜かな，可用〜てる、〜ちゃう這類縮約；不要用敬語。第一人稱能省就省。"
        ),
        Situation(
            id: "close", label: "親密", hint: "另一半、曖昧對象：溫柔的タメ口",
            guide: "對象是另一半或曖昧中的人。溫柔親暱的タメ口，語尾柔和（〜ね、〜な、〜よ），像傳給喜歡的人的 LINE；原話有的甜要表達出來，但不要自己加情話。"
        ),
    ]

    static let th: [Situation] = [
        Situation(
            id: "client", label: "客戶", hint: "正式有禮：คุณ、รบกวน…、ขอบคุณมาก",
            guide:
                "對象是泰國客戶或合作廠商。正式有禮：稱對方 คุณ（有名字就 คุณ＋名字）；請求用 รบกวน…หน่อย／…ด้วย，道謝用 ขอบคุณมาก；不用網路寫法（คับ、ค่า）與俚語。"
        ),
        Situation(
            id: "friend", label: "朋友", hint: "輕鬆口語：เรา、นะ，不用粗口",
            guide: "對象是泰國朋友。輕鬆自然的口語：自稱 เรา，稱對方用名字（原話有說）或 แก；用 นะ、อะ、เนอะ 讓語氣自然；不要書面腔，也不要用 กู、มึง 這類粗口。"
        ),
        Situation(
            id: "girl", label: "女生朋友", hint: "親切溫柔：เรา、เธอ、นะ，體貼不生疏",
            guide:
                "對象是泰國的女生朋友。親切、溫柔、有禮但不生疏：自稱 เรา，稱她用名字（原話有說）或 เธอ；用 นะ 讓語氣軟；關心的話講得體貼自然；不用粗口，也不要自己加曖昧或示愛的話。"
        ),
        Situation(
            id: "close", label: "親密", hint: "另一半：เค้า、ตัวเอง、นะ，甜但自然",
            guide: "對象是另一半或曖昧中的人。甜而自然：自稱 เค้า，稱對方 ตัวเอง（或原話說的暱稱）；用 นะ、จ้า 讓語氣甜；原話有的甜要表達出來，但不要自己加情話。"
        ),
    ]

    // MARK: 翻譯目標（設定裡排好；鍵盤長按時照這個順序排開）

    static let maxTargets = 4
    /// 第一次用的預設：三種常見情境（泰文女生朋友、日文客戶、英文客戶）
    static let defaultTargets = ["th:girl", "ja:client", "en:client"]

    struct Target: Hashable, Identifiable {
        let lang: OutputLang
        let situation: Situation
        var id: String { key }
        var key: String { "\(lang.rawValue):\(situation.id)" }
        var label: String { "\(lang.label)・\(situation.label)" }

        init(lang: OutputLang, situation: Situation) {
            self.lang = lang
            self.situation = situation
        }

        init?(key: String) {
            let parts = key.split(separator: ":").map(String.init)
            guard parts.count == 2, let l = OutputLang(rawValue: parts[0]), l != .zh,
                let s = Translate.situations(l).first(where: { $0.id == parts[1] })
            else { return nil }
            self.init(lang: l, situation: s)
        }
    }

    private static var d: UserDefaults { Bridge.shared }

    static var targets: [Target] {
        get {
            let keys = d.array(forKey: "translateTargets") as? [String] ?? defaultTargets
            var seen = Set<String>()
            return keys.compactMap(Target.init(key:)).filter { seen.insert($0.key).inserted }.prefix(maxTargets).map { $0 }
        }
        set { d.set(newValue.prefix(maxTargets).map(\.key), forKey: "translateTargets") }
    }

    /// 打上的字要不要附原文：「譯文⏎（中文原文）」（Mac 版 withOriginal 同一個格式）
    static var withOriginal: Bool {
        get { d.bool(forKey: "translateWithOriginal") }
        set { d.set(newValue, forKey: "translateWithOriginal") }
    }

    /// 附原文的格式：譯文換行，全形括號包中文
    static func attachOriginal(_ text: String, zh: String) -> String {
        withOriginal ? text + "\n（" + zh + "）" : text
    }

    /// 說話者口吻（泰文 ครับ／ค่ะ、日文口語 僕／私）；沒選＝中性說法
    static var speaker: SpeakerVoice {
        get { SpeakerVoice(rawValue: d.string(forKey: "speakerVoice") ?? "") ?? .unset }
        set { d.set(newValue.rawValue, forKey: "speakerVoice") }
    }

    // MARK: 這一句要翻成什麼（鍵盤寫、app 開始聽時取走）

    static func setNext(_ t: Target?) {
        d.set(t?.key ?? "", forKey: "nextOutput")
    }

    static func takeNext() -> Target? {
        let k = d.string(forKey: "nextOutput") ?? ""
        d.removeObject(forKey: "nextOutput")
        return Target(key: k)
    }
}
