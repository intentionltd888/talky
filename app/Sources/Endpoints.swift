// Endpoints — 自填端點的設定（OpenAI 相容端點／Anthropic 金鑰）
//
// v1 就含 OpenAI 相容端點與 Anthropic 金鑰兩條，其餘相容端點一併接上。
// 沒有 Claude Code、也不想跑本機模型的人（或公司有自己的閘道）走這兩條。
// 金鑰放鑰匙圈（generic password，service＝bundle id），不進 UserDefaults、不進記錄檔、不進診斷檔。
// 端點與模型名放 UserDefaults（不是機密）。

import Foundation
import Security

enum KeychainStore {
    static let service = Bundle.main.bundleIdentifier ?? "ltd.intention.talky"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else {
            return nil
        }
        return String(data: d, encoding: .utf8)
    }

    /// 空字串＝刪掉
    static func set(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, let d = v.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = d
        add[kSecAttrLabel as String] = "Talky \(account)"
        let st = SecItemAdd(add as CFDictionary, nil)
        if st != errSecSuccess { TalkyLog.write("keychain set \(account) fail: \(st)") }
    }
}

enum Endpoints {
    private static let d = UserDefaults.standard

    // ── OpenAI 相容端點（任何 /v1/chat/completions：OpenAI、Groq、OpenRouter、LM Studio、公司閘道…）──
    static var openAIBase: String {
        get { d.string(forKey: "openaiBase") ?? "https://api.openai.com/v1" }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "openaiBase") }
    }
    static var openAIModel: String {
        get { d.string(forKey: "openaiModel") ?? "gpt-4o-mini" }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "openaiModel") }
    }
    static var openAIKey: String {
        get { KeychainStore.get("openai") ?? "" }
        set { KeychainStore.set("openai", newValue) }
    }
    /// 「填過」＝使用者真的動過：有金鑰，或自己改過端點／模型（預設值不算，不然狀態燈一開始就假綠）。金鑰可空：本機端點常不需要
    static var openAIFilled: Bool {
        let touched = d.string(forKey: "openaiBase") != nil || d.string(forKey: "openaiModel") != nil
        return (!openAIKey.isEmpty || touched) && !openAIBase.isEmpty && !openAIModel.isEmpty
    }
    /// 送請求的完整 URL：使用者填到 /v1 或填到 /chat/completions 都吃
    static var openAIChatURL: String {
        let b = openAIBase
        if b.hasSuffix("/chat/completions") { return b }
        return (b.hasSuffix("/") ? String(b.dropLast()) : b) + "/chat/completions"
    }

    // ── Anthropic 金鑰（Messages API；base 可改成自家代理）──
    static var anthropicBase: String {
        get { d.string(forKey: "anthropicBase") ?? "https://api.anthropic.com" }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anthropicBase") }
    }
    static var anthropicModel: String {
        get { d.string(forKey: "anthropicModel") ?? "claude-sonnet-5" }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anthropicModel") }
    }
    static var anthropicKey: String {
        get { KeychainStore.get("anthropic") ?? "" }
        set { KeychainStore.set("anthropic", newValue) }
    }
    static var anthropicFilled: Bool { !anthropicKey.isEmpty && !anthropicModel.isEmpty }

    /// 給狀態燈看的一句（不露金鑰）
    static func host(_ base: String) -> String { URL(string: base)?.host ?? base }
}
