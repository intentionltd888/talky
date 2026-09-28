// MacRelay — 用「你自己的 Mac」的訂閱整理與翻譯（Mac 版 Talky → 設定 → iPhone 打開，用相機掃 QR 碼配對）
//
// 為什麼繞一台 Mac：Anthropic 不准第三方 app 直接登入 Claude 訂閱（2026），ChatGPT 也沒開放給第三方用訂閱；
// 合規的路＝使用者自己的 Mac 上跑官方 Claude Code／Codex（在 Mac 上用 Anthropic／OpenAI 自己的登入頁登入），
// iPhone 只把一句話加密送過去。iPhone 不碰任何帳號。
// 協定（跟 Mac 版 app/Sources/RelayCore.swift 同一份）：POST /talky/v1，本體 {"v":1,"id":配對編號,"b":ChaChaPoly 加密的 JSON}；
// 金鑰只在配對時從 QR 碼拿一次，存鑰匙圈。連線直接用 Network.framework：同時試 Mac 的每個位址（.local／區網／Tailscale），
// 誰先連上用誰；內容本來就加密，不走 HTTPS 也看不到。

import CryptoKit
import Foundation
import Network

struct MacPairing: Codable, Equatable {
    let id: String
    let name: String
    let hosts: [String]
    let port: UInt16
}

enum MacRelay {
    // MARK: 配對

    private static let pairingKey = "macPairing"

    static var pairing: MacPairing? {
        guard let d = UserDefaults.standard.data(forKey: pairingKey) else { return nil }
        return try? JSONDecoder().decode(MacPairing.self, from: d)
    }

    static var isPaired: Bool { pairing != nil && key != nil }

    /// talky://pair?v=1&id=…&k=…&n=…&h=…&p=…
    static func pair(from url: URL) -> Result<MacPairing, Error> {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return .failure(RelayClientError("配對碼壞了"))
        }
        func q(_ n: String) -> String? { items.first { $0.name == n }?.value }
        guard q("v") == "1", let id = q("id"), !id.isEmpty, let k = q("k"), let keyData = base64urlDecode(k),
            keyData.count == 32, let h = q("h"), let p = q("p"), let port = UInt16(p)
        else { return .failure(RelayClientError("配對碼壞了：請在 Mac 版 Talky 重新顯示 QR 碼")) }
        let hosts = h.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !hosts.isEmpty else { return .failure(RelayClientError("配對碼裡沒有 Mac 的位址")) }
        let pairing = MacPairing(id: id, name: q("n") ?? "Mac", hosts: hosts, port: port)
        guard RelayKeychain.save(keyData, account: id) else { return .failure(RelayClientError("存不了配對金鑰")) }
        if let old = self.pairing, old.id != id { RelayKeychain.delete(account: old.id) }
        UserDefaults.standard.set(try? JSONEncoder().encode(pairing), forKey: pairingKey)
        lastHost = nil
        Bridge.log("app", "配對了一台 Mac（\(hosts.count) 個位址）")
        return .success(pairing)
    }

    static func unpair() {
        if let p = pairing { RelayKeychain.delete(account: p.id) }
        UserDefaults.standard.removeObject(forKey: pairingKey)
        lastHost = nil
    }

    private static var key: SymmetricKey? {
        guard let p = pairing, let d = RelayKeychain.load(account: p.id), d.count == 32 else { return nil }
        return SymmetricKey(data: d)
    }

    // MARK: 呼叫

    /// 送一個請求給 Mac，回傳解密後的內容（{"ok":true,…}）；ok＝false 也當成錯誤丟出來
    static func call(_ payload: [String: Any], timeout: Double) async throws -> [String: Any] {
        guard let p = pairing, let k = key else { throw RelayClientError("還沒配對 Mac") }
        var msg = payload
        msg["ts"] = Date().timeIntervalSince1970
        let plain = try JSONSerialization.data(withJSONObject: msg)
        let sealed = try ChaChaPoly.seal(plain, using: k, authenticating: Data("talky/v1/\(p.id)".utf8))
        let body = try JSONSerialization.data(withJSONObject: [
            "v": 1, "id": p.id, "b": sealed.combined.base64EncodedString(),
        ])
        guard let host = await reachableHost(p) else {
            throw RelayClientError("連不到你的 Mac（要在同一個網路或 Tailscale；Mac 版 Talky 的「iPhone」要開著）")
        }
        let (status, respBody) = try await HTTPOverTCP.post(
            host: host, port: p.port, path: "/talky/v1", body: body, timeout: timeout)
        let obj = (try? JSONSerialization.jsonObject(with: respBody)) as? [String: Any] ?? [:]
        guard status == 200, let b = obj["b"] as? String, let combined = Data(base64Encoded: b) else {
            if status == 403 { unreachable() }
            throw RelayClientError(obj["error"] as? String ?? "Mac 回了 HTTP \(status)")
        }
        let box = try ChaChaPoly.SealedBox(combined: combined)
        let out = try ChaChaPoly.open(box, using: k, authenticating: Data("talky/v1/resp/\(p.id)".utf8))
        guard let res = try JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            throw RelayClientError("Mac 回的東西看不懂")
        }
        if res["ok"] as? Bool != true { throw RelayClientError(res["error"] as? String ?? "Mac 那邊沒成功") }
        return res
    }

    // MARK: 找得到 Mac 的那個位址（同時試，誰先連上用誰；記 5 分鐘）

    private static var lastHost: (String, Date)?

    private static func unreachable() { lastHost = nil }

    static func reachableHost(_ p: MacPairing) async -> String? {
        if let (h, t) = lastHost, Date().timeIntervalSince(t) < 300, p.hosts.contains(h) { return h }
        let found = await withTaskGroup(of: String?.self) { group -> String? in
            for h in p.hosts {
                group.addTask { await HTTPOverTCP.canConnect(host: h, port: p.port, timeout: 2) ? h : nil }
            }
            for await r in group {
                if let r {
                    group.cancelAll()
                    return r
                }
            }
            return nil
        }
        if let found { lastHost = (found, Date()) }
        return found
    }

    private static func base64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}

struct RelayClientError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// 配對金鑰放鑰匙圈（只有 Talky 主 app 讀；鍵盤用不到）
enum RelayKeychain {
    private static let service = "ltd.intention.talky.relay"

    static func load(account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        delete(account: account)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecValueData as String: data,
            // 待命中的背景整理也要讀得到：開機後解鎖過一次就能讀
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// 最小 HTTP/1.1 用戶端（Network.framework 直連；Mac 端只回 Content-Length 的 JSON 然後關線）
enum HTTPOverTCP {
    static func canConnect(host: String, port: UInt16, timeout: Double) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let once = Once(cont)
            c.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    once.resume(true)
                    c.cancel()
                case .failed, .cancelled:
                    once.resume(false)
                case .waiting:
                    // 等待中（沒網路、被拒）＝這條不通
                    once.resume(false)
                    c.cancel()
                default:
                    break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(false)
                c.cancel()
            }
        }
    }

    static func post(host: String, port: UInt16, path: String, body: Data, timeout: Double) async throws -> (Int, Data) {
        var req = "POST \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nContent-Type: application/json\r\n"
        req += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let payload = Data(req.utf8) + body
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Int, Data), Error>) in
            let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let once = OnceThrowing(cont)
            var buffer = Data()
            func finish() {
                // 狀態列＋標頭＋本體
                guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
                    let head = String(data: buffer[..<end.lowerBound], encoding: .utf8)
                else {
                    once.resume(throwing: RelayClientError("Mac 回的東西看不懂"))
                    return
                }
                let status = Int(head.split(separator: " ").dropFirst().first ?? "") ?? 0
                once.resume(returning: (status, Data(buffer[end.upperBound...])))
            }
            func read() {
                c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, err in
                    if let data { buffer.append(data) }
                    if done || err != nil {
                        finish()
                        c.cancel()
                    } else {
                        read()
                    }
                }
            }
            c.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    c.send(content: payload, completion: .contentProcessed { e in
                        if let e { once.resume(throwing: e) } else { read() }
                    })
                case .failed(let e):
                    once.resume(throwing: e)
                case .waiting(let e):
                    once.resume(throwing: e)
                    c.cancel()
                default:
                    break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(throwing: RelayClientError("Mac 太久沒回（\(Int(timeout)) 秒）"))
                c.cancel()
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<Bool, Never>?
    init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
    func resume(_ v: Bool) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: v)
    }
}

private final class OnceThrowing: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<(Int, Data), Error>?
    init(_ c: CheckedContinuation<(Int, Data), Error>) { cont = c }
    func resume(returning v: (Int, Data)) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: v)
    }
    func resume(throwing e: Error) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(throwing: e)
    }
}
