// LocalLLM — 本機潤飾引擎（llama-server）的路徑解析與模式選擇
//
// Talky 的潤飾三段鏈：
//   ① Claude Code CLI（偵測到 claude 且能跑就用，用的是使用者自己的訂閱額度）
//   ② 本機模型 Qwen3-4B（選配下載 2.5GB；沒有 Claude Code 的人走這條）
//   ③ 都不行 → 只貼原稿＋確定性清理（TextUtil：簡轉繁、標點全形、幻聽過濾）
//
// 這個檔只負責「找得到什麼」與「現在該用哪條」；引擎的起停在 Dictation.swift（TalkyServers）。

import Foundation

/// 潤飾模式（設定頁「用什麼來整理」）
enum PolishMode: String {
    case claudeCLI, codex, ollama, local, openai, anthropic, off

    /// 使用者沒選過時的預設：裝著 claude CLI 就用它，否則用本機模型
    static var current: PolishMode {
        guard let raw = UserDefaults.standard.string(forKey: "polishMode"),
            let m = PolishMode(rawValue: raw)
        else {
            // 沒選過：先用你已經有的訂閱（Claude Code → ChatGPT 桌面版的 Codex），都沒有才本機模型
            if ClaudeCLI.available { return .claudeCLI }
            if CodexCLI.available { return .codex }
            return .local
        }
        // 選了 Claude Code／Codex 但這台後來沒有了 → 自動退本機模型，不讓潤飾停在死路
        if m == .claudeCLI, !ClaudeCLI.available { return .local }
        if m == .codex, !CodexCLI.available { return .local }
        return m
    }
    /// 精靈簡稱（面板「整理中，用你的 ___」）
    var shortLabel: String {
        switch self {
        case .claudeCLI: return "Claude"
        case .codex: return "ChatGPT"
        case .ollama: return "Ollama"
        case .local: return "內建模型"
        case .openai: return "你填的端點"
        case .anthropic: return "Anthropic 金鑰"
        case .off: return "不整理"
        }
    }
    static func set(_ m: PolishMode) {
        UserDefaults.standard.set(m.rawValue, forKey: "polishMode")
    }

    var label: String {
        switch self {
        case .claudeCLI: return "你的 Claude"
        case .codex: return "你的 ChatGPT"
        case .ollama: return "Ollama（本機）"
        case .local: return "內建模型"
        case .openai: return "自填 OpenAI 相容端點"
        case .anthropic: return "自填 Anthropic 金鑰"
        case .off: return "不整理，直接貼原稿"
        }
    }
}

enum LocalLLM {
    static var modelFile: String { ModelCatalog.qwen.file }
    static var modelSizeBytes: Int64 { ModelCatalog.qwen.bytes }

    /// llama-server：打包版（Resources/llama/）優先，退開發機 brew
    static func serverBinary() -> String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("llama/llama-server").path)
        }
        candidates.append("/opt/homebrew/bin/llama-server")
        candidates.append("/usr/local/bin/llama-server")
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 潤飾模型實體路徑（借鄰居的優先，見 SharedPaths）
    static func modelPath() -> String? {
        SharedPaths.modelSearchPaths(modelFile).first {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    static var modelReady: Bool { modelPath() != nil }
}

// ── 確定性守門（潤飾輸出的機械保底，不靠 prompt）─────────────────

enum PolishGuards {
    /// 中文佔字母類字元的比例（判斷輸出語言有沒有翻掉）
    static func cjkRatio(_ s: String) -> Double {
        var cjk = 0
        var letters = 0
        for ch in s.unicodeScalars {
            let isCJK = (0x4E00...0x9FFF).contains(Int(ch.value))
            if isCJK {
                cjk += 1
                letters += 1
            } else if CharacterSet.letters.contains(ch) {
                letters += 1
            }
        }
        return letters == 0 ? 1 : Double(cjk) / Double(letters)
    }

    /// 語言保底：輸入以中文為主、輸出中文比例驟降（小模型遇髒段會整段翻成英文）→ 判定翻車，退原稿
    static func languageFlipped(input: String, output: String) -> Bool {
        cjkRatio(input) > 0.6 && cjkRatio(output) < 0.4
    }

    /// 輸出過濾器：coding agent 型的 CLI 偶爾會在整理稿前後多講一句話
    /// （「好的，以下是整理後的內容：」「需要我再調整嗎？」）。只留整理稿本體。
    static func stripChatter(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 前綴：第一行像「開場白＋冒號」且下面還有內容 → 砍掉第一行
        let lines = t.components(separatedBy: "\n")
        if lines.count > 1 {
            let first = lines[0].trimmingCharacters(in: .whitespaces)
            let opener = ["以下是", "好的", "整理後", "這是", "幫你"]
            if first.count <= 30, first.hasSuffix("："), opener.contains(where: { first.hasPrefix($0) })
            {
                t = lines.dropFirst().joined(separator: "\n").trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
        }
        // 後綴：最後一行是反問／招呼
        let tail = ["需要我", "還需要", "要我再", "希望這", "如果你"]
        var parts = t.components(separatedBy: "\n")
        if parts.count > 1 {
            let last = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
            if last.count <= 40, tail.contains(where: { last.hasPrefix($0) }) {
                parts.removeLast()
                t = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 整段被包在程式碼圍籬裡
        if t.hasPrefix("```"), t.hasSuffix("```") {
            var inner = t.components(separatedBy: "\n")
            inner.removeFirst()
            if inner.last?.trimmingCharacters(in: .whitespaces) == "```" { inner.removeLast() }
            t = inner.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }
}
