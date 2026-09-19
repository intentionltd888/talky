// Translate — 翻譯模式：講中文、貼外語（左 ⌘ 連按兩下）
//
// 左 ⌘ 連按兩下進翻譯模式，選要翻成哪種語言；
// 每種語言翻出來都要符合當地的口語。
//
// 核心設計：九種語言各有一套「對誰講話」的敬語與稱謂，不讓使用者每種語言各選一次——
// 一個「對象」設定（朋友／同事／不認識的人）驅動全部語言；泰文另加一次「我的性別」（語尾 ครับ／ค่ะ）。
// 翻譯是「這一次口述要做什麼」（DictationMode）這條軸上的第一個非預設模式；「誰來做」仍是 PolishMode 那條軸。

import Foundation

/// 一次 LLM 任務的三件事：system 規則、少樣本、請求前綴。整理與翻譯各一份，走同一套路由與大腳。
struct LLMTask {
    let name: String
    let system: String
    let fewshot: [(String, String)]
    let prefix: String
}

enum TranslateTarget: String, CaseIterable, Identifiable {
    case en, ja, ko, th, vi, id, es, fr, de, pt, zhHans, yue
    var id: String { rawValue }

    /// 核心 8（照台灣使用者真的會對誰講話排；泰文直接進核心）
    static let core: [TranslateTarget] = [.en, .ja, .ko, .th, .vi, .id, .es, .fr]
    /// 選配 4（設定一個開關全開）
    static let extra: [TranslateTarget] = [.de, .pt, .zhHans, .yue]
    static var enabled: [TranslateTarget] { Translate.extraLangs ? core + extra : core }

    /// 面板籤（兩個字，排得下十二顆）
    var chip: String {
        switch self {
        case .en: return "英文"
        case .ja: return "日文"
        case .ko: return "韓文"
        case .th: return "泰文"
        case .vi: return "越南"
        case .id: return "印尼"
        case .es: return "西文"
        case .fr: return "法文"
        case .de: return "德文"
        case .pt: return "葡文"
        case .zhHans: return "簡中"
        case .yue: return "粵語"
        }
    }
    /// 全名（設定頁、面板「翻成___中」）
    var name: String {
        switch self {
        case .en: return "英文"
        case .ja: return "日文"
        case .ko: return "韓文"
        case .th: return "泰文"
        case .vi: return "越南文"
        case .id: return "印尼文"
        case .es: return "西班牙文"
        case .fr: return "法文"
        case .de: return "德文"
        case .pt: return "葡萄牙文（巴西）"
        case .zhHans: return "簡體中文"
        case .yue: return "粵語（書面）"
        }
    }
    /// 給模型看的名稱
    var promptName: String {
        switch self {
        case .en: return "English (US)"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .th: return "Thai"
        case .vi: return "Vietnamese"
        case .id: return "Indonesian"
        case .es: return "Spanish (neutral Latin American)"
        case .fr: return "French"
        case .de: return "German"
        case .pt: return "Brazilian Portuguese"
        case .zhHans: return "Simplified Chinese (mainland vocabulary)"
        case .yue: return "written Cantonese (Hong Kong)"
        }
    }
    /// 本機 4B 小模型翻這幾種口語不穩（面板標示，不擋）
    var weakOnSmallModel: Bool { [.th, .vi, .id].contains(self) }

    /// 該語言的落差 → 我們的預設。audience／gender 決定敬語與語尾。
    func rules(audience: TranslateAudience, gender: SpeakerGender) -> String {
        switch self {
        case .en:
            return """
                - 中文語氣詞（啦、嘛、欸、喔）沒有對應，直接拿掉；不要硬翻成 "you know"
                - 「辛苦了」「麻煩你了」這類客套沒有直譯，改成功能對等的說法（Thanks for handling this / Appreciate it）
                - 中文的委婉（「不太方便」「可能沒辦法」）要講明但不變粗（I'd rather not / That won't work for me）
                - 美式拼字與用法；語氣照對象：\(audience.en)
                """
        case .ja:
            return """
                - 敬語層級照對象：\(audience.ja)。不用尊敬語・謙讓語（會過頭）
                - 主詞能省就省；不要每句都寫「あなた」
                - 人名不轉片假名，維持原文寫法
                - 外來語用日本人真的在用的片假名寫法；沒有慣用寫法的英文術語保留英文
                """
        case .ko:
            return """
                - 語尾照對象：\(audience.ko)
                - 不隨便用 반말；只在對象是朋友且句子明顯親近時才用
                - 稱謂不亂加 님／씨；人名維持原文寫法
                """
        case .th:
            return """
                - 語尾照講話者性別：\(gender.th)
                - 語氣照對象：\(audience.th)
                - 泰文不用句號、詞之間不加空格（句子之間用一個空格分開）；不用 555 這種網路用法
                """
        case .vi:
            return """
                - 稱謂代詞照對象：\(audience.vi)；關係不確定就用中性的 mình／bạn
                - 聲調符號一律完整，絕不省略
                """
        case .id:
            return """
                - 第二人稱照對象：\(audience.id)；不用雅加達俚語（lo／gue）
                - 用標準印尼文，不混馬來文用法
                """
        case .es:
            return """
                - 用拉丁美洲中性西班牙文，不用 vosotros
                - 第二人稱照對象：\(audience.es)
                """
        case .fr:
            return """
                - 第二人稱照對象：\(audience.fr)
                - 用法國本土慣用說法；不用魁北克特有用法
                """
        case .de:
            return """
                - 第二人稱照對象：\(audience.de)
                - 用德國標準德文
                """
        case .pt:
            return """
                - 用巴西葡萄牙文（você），不用葡萄牙本土用法
                - 語氣照對象：\(audience.en)
                """
        case .zhHans:
            return """
                - 這不是翻譯，是詞彙轉換：改用中國大陸慣用詞（軟體→软件、影片→视频、伺服器→服务器、資料→数据、網路→网络、滑鼠→鼠标、程式→程序），語氣與句構不動
                - 全部輸出簡體字
                """
        case .yue:
            return """
                - 用香港書面粵語（唔／喺／嘅／咗 等口語字可用），不寫成普通話白話文
                - 用繁體字、香港慣用詞（巴士、的士、返工）
                """
        }
    }

    /// 輸出像不像目標語言（字元集粗檢；不像＝判失敗、貼原文）
    func looksLike(_ s: String) -> Bool {
        var latin = 0, cjk = 0, kana = 0, hangul = 0, thai = 0, letters = 0
        for u in s.unicodeScalars {
            let v = Int(u.value)
            var isLetter = false
            if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v) || (0x1E00...0x1EFF).contains(v) {
                latin += 1; isLetter = true
            } else if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                cjk += 1; isLetter = true
            } else if (0x3040...0x30FF).contains(v) {
                kana += 1; isLetter = true
            } else if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) {
                hangul += 1; isLetter = true
            } else if (0x0E00...0x0E7F).contains(v) {
                thai += 1; isLetter = true
            }
            if isLetter { letters += 1 }
        }
        guard letters > 0 else { return false }
        func r(_ n: Int) -> Double { Double(n) / Double(letters) }
        switch self {
        // 門檻放到 0.3：口述常夾英文術語（implementation、elegant 本來就該保留），拉丁字母會吃掉一半比例
        case .ja: return (kana > 0 && r(kana + cjk) > 0.3 && hangul == 0 && thai == 0) || (r(cjk) > 0.6 && hangul == 0 && thai == 0 && kana == 0 && letters <= 6)
        case .ko: return r(hangul) > 0.3
        case .th: return r(thai) > 0.3
        case .zhHans, .yue: return r(cjk) > 0.3 && kana == 0 && hangul == 0 && thai == 0
        default: return r(latin) > 0.6 && r(cjk) < 0.1
        }
    }
}

enum TranslateAudience: String, CaseIterable {
    case friend, colleague, stranger
    var label: String {
        switch self {
        case .friend: return "朋友"
        case .colleague: return "同事"
        case .stranger: return "不認識的人"
        }
    }
    // 各語言的敬語落點
    var en: String {
        switch self {
        case .friend: return "輕鬆自然，可用縮寫（I'm、gonna 不用）"
        case .colleague: return "客氣但不生硬，像同事間的訊息"
        case .stranger: return "禮貌、完整句、不用俚語"
        }
    }
    var ja: String {
        switch self {
        case .friend: return "一律普通體（〜だ／〜だよ／〜だよね／〜と思う／〜かな），像朋友傳 LINE；【禁止】です・ます"
        case .colleague: return "です・ます 體"
        case .stranger: return "です・ます 體，開頭可加「すみません」類緩衝"
        }
    }
    var ko: String {
        switch self {
        case .friend: return "해요체（-요）；很親近的句子才可用 반말"
        case .colleague: return "해요체（-요）"
        case .stranger: return "합니다체（-습니다／-ㅂ니다）"
        }
    }
    var th: String {
        switch self {
        case .friend: return "口語自然，可用 นะ／เนอะ 這類軟化語氣"
        case .colleague: return "客氣自然，像同事傳訊息（語尾要不要加 ครับ／ค่ะ 只看上面的性別規則）"
        case .stranger: return "禮貌正式，第二人稱用 คุณ（語尾要不要加 ครับ／ค่ะ 只看上面的性別規則）"
        }
    }
    var vi: String {
        switch self {
        case .friend: return "同輩用 mình／bạn，親近可用 tớ／cậu"
        case .colleague: return "mình／bạn 或 tôi／anh・chị，客氣中性"
        case .stranger: return "tôi 配 anh／chị，正式客氣"
        }
    }
    var id: String {
        switch self {
        case .friend: return "kamu／aku"
        case .colleague: return "kamu／saya"
        case .stranger: return "Anda／saya"
        }
    }
    var es: String {
        switch self {
        case .friend: return "tú"
        case .colleague: return "tú，語氣客氣"
        case .stranger: return "usted"
        }
    }
    var fr: String {
        switch self {
        case .friend: return "tu"
        case .colleague: return "vous（除非句子明顯很熟）"
        case .stranger: return "vous"
        }
    }
    var de: String {
        switch self {
        case .friend: return "du"
        case .colleague: return "Sie（除非句子明顯很熟）"
        case .stranger: return "Sie"
        }
    }
}

enum SpeakerGender: String, CaseIterable {
    case unset, male, female
    var label: String {
        switch self {
        case .unset: return "不設定"
        case .male: return "男"
        case .female: return "女"
        }
    }
    var th: String {
        switch self {
        case .unset: return "不知道講話者性別：句尾【絕對不要】出現 ครับ／ค่ะ／คะ，要軟化語氣只能用 นะ；第一人稱用 เรา 或直接省略，不用 ผม／ดิฉัน；不要猜性別"
        case .male: return "講話者是男性：句尾用 ครับ，第一人稱 ผม"
        case .female: return "講話者是女性：句尾用 ค่ะ（問句用 คะ），第一人稱 เรา 或 ดิฉัน（正式）"
        }
    }
}

enum Translate {
    // ── 設定（UserDefaults）──
    static var enabledHotkey: Bool {
        get { UserDefaults.standard.object(forKey: "translateHotkey") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "translateHotkey") }
    }
    static var target: TranslateTarget {
        get {
            let t = TranslateTarget(rawValue: UserDefaults.standard.string(forKey: "translateTarget") ?? "") ?? .en
            return TranslateTarget.enabled.contains(t) ? t : .en
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "translateTarget") }
    }
    static var audience: TranslateAudience {
        get { TranslateAudience(rawValue: UserDefaults.standard.string(forKey: "translateAudience") ?? "") ?? .colleague }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "translateAudience") }
    }
    static var gender: SpeakerGender {
        get { SpeakerGender(rawValue: UserDefaults.standard.string(forKey: "speakerGender") ?? "") ?? .unset }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "speakerGender") }
    }
    /// 貼「譯文＋（原文）」還是只貼譯文
    static var withOriginal: Bool {
        get { UserDefaults.standard.bool(forKey: "translateWithOriginal") }
        set { UserDefaults.standard.set(newValue, forKey: "translateWithOriginal") }
    }
    static var extraLangs: Bool {
        get { UserDefaults.standard.bool(forKey: "translateExtraLangs") }
        set { UserDefaults.standard.set(newValue, forKey: "translateExtraLangs") }
    }

    // ── 依前景 app 記語言（例：LINE 對泰國同事、Slack 對日本客戶）──
    private static let byAppKey = "translateTargetByApp"
    /// 開始翻譯時的預選：這個 app 上次用的 → 全域上次用的（＝target）→ 設定預設
    static func preselect(forApp bundleID: String?) -> TranslateTarget {
        if let b = bundleID,
            let d = UserDefaults.standard.dictionary(forKey: byAppKey) as? [String: String],
            let raw = d[b], let t = TranslateTarget(rawValue: raw), TranslateTarget.enabled.contains(t)
        {
            return t
        }
        return target
    }
    /// 點了籤＝記成全域上次、也記成這個 app 的
    static func remember(_ t: TranslateTarget, forApp bundleID: String?) {
        target = t
        guard let b = bundleID else { return }
        var d = (UserDefaults.standard.dictionary(forKey: byAppKey) as? [String: String]) ?? [:]
        d[b] = t.rawValue
        UserDefaults.standard.set(d, forKey: byAppKey)
    }

    // ── prompt ──

    /// 跨語言七條
    static let commonRules = """
        - 忠於原意翻成目標語言的自然口語書面（像當地人傳訊息會寫的句子），不逐字硬翻
        - 中英夾雜的專業術語照原樣（目標是英文時自然融進句子），不翻、不解釋
        - 人名、品牌、地名不翻、不轉寫
        - 數字、日期、時間、貨幣的寫法照目標語言的習慣
        - 講話中途改口時（「啊不對」「不是」「說錯了」）只翻改口後的版本；口語贅字（呃、嗯、然後、對對對）拿掉；明顯列舉時排成條列
        - 不新增內容、不解釋、不加表情符號、不加「翻譯：」之類前綴、不加引號或 markdown
        - 【人稱鐵律】誰說、誰做、誰付錢，一個字都不能對調
        - 【事實鐵律】數字、日期、金額、名字、肯定與否定照原文，不可翻轉
        - 關係不確定就用中性說法，不猜；寧可少一點親近，不要錯稱謂
        """

    static func prefix(_ t: TranslateTarget) -> String {
        "把以下口述翻成\(t.name)，只輸出譯文：\n\n"
    }

    static func system(_ t: TranslateTarget) -> String {
        var glossary = ""
        if let g = TextUtil.localGlossary() {
            glossary = "\n- 這些專有名詞若音近請修正並照這個寫法保留，不翻：\(g)"
        }
        return """
            你是語音輸入法的翻譯器，不是對話助理。使用者用中文（可能夾英文）口述，你要把逐字稿翻成 \(t.promptName)，讓對方讀起來像當地人寫的訊息。
            通用規則：
            \(commonRules)\(glossary)
            \(t.name)的規則：
            \(t.rules(audience: audience, gender: gender))
            只輸出\(t.name)譯文本體。
            """
    }

    /// 少樣本：示範「改口只留後者」與「術語保留」；只給英日兩種完整例，其餘語言靠規則（避免例句品質拖累）
    static func fewshot(_ t: TranslateTarget) -> [(String, String)] {
        let p = prefix(t)
        switch t {
        case .en:
            return [
                (p + "嗯那個這個 implementation 我覺得很 elegant,然後 deadline 是禮拜五對不對,啊不對是禮拜四。",
                 "I think this implementation is really elegant. The deadline is Thursday, right?"),
                (p + "呃就是麻煩你先看一下那個檔案嘛,我等一下再跟你說,對對對。",
                 "Could you take a look at the file first? I'll get back to you in a bit."),
            ]
        case .ja:
            let polite = audience != .friend
            return [
                (p + "嗯那個這個 implementation 我覺得很 elegant,然後 deadline 是禮拜五對不對,啊不對是禮拜四。",
                 polite ? "この implementation はとても elegant だと思います。締め切りは木曜日ですよね？" : "この implementation、すごく elegant だと思う。締め切りは木曜だよね？"),
            ]
        default:
            return []
        }
    }

    static func task(for t: TranslateTarget) -> LLMTask {
        LLMTask(name: "translate-\(t.rawValue)", system: system(t), fewshot: fewshot(t), prefix: prefix(t))
    }
}
