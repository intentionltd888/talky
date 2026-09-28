// RelayCore — iPhone ↔ Mac 中繼的底層（不碰 app 其他部分，測試工具也能單獨編）
//
// 為什麼要有中繼：iPhone 跑不了 Claude Code／Codex，而 Anthropic 不准第三方 app 直接登入 Claude 訂閱
// （code.claude.com/docs/en/legal-and-compliance，2026），ChatGPT 也沒有開放給第三方用訂閱。
// 合規的路＝使用者自己的 Mac 上跑官方、沒改過的 CLI、用自己的帳號登入；iPhone 把一句話送過來請它整理或翻譯。
//
// 安全（預設關，打開才聽）：
// ・只接私有網段／Tailscale（100.64/10、fd7a::/…）／本機來的連線，其他一律斷線
// ・每個請求整包用配對金鑰加密＋驗證（ChaCha20-Poly1305；AAD 綁配對編號），區網上看不到內容、偷不到金鑰
// ・時間戳 ±120 秒＋nonce 不重複（擋重放）；每分鐘最多 60 次；本體最大 64KB
// ・金鑰只在 QR 碼裡出現；換一組就讓舊 iPhone 失效

import CryptoKit
import Foundation
import Network

enum RelayCore {
    static let version = 1
    static let path = "/talky/v1"

    // MARK: 加密信封

    static func requestAAD(_ id: String) -> Data { Data("talky/v1/\(id)".utf8) }
    static func responseAAD(_ id: String) -> Data { Data("talky/v1/resp/\(id)".utf8) }

    static func seal(_ obj: [String: Any], key: SymmetricKey, aad: Data) throws -> String {
        let plain = try JSONSerialization.data(withJSONObject: obj)
        return try ChaChaPoly.seal(plain, using: key, authenticating: aad).combined.base64EncodedString()
    }

    /// 解開＋驗證；回傳（內容, nonce 位元組）
    static func open(_ b64: String, key: SymmetricKey, aad: Data) throws -> ([String: Any], Data) {
        guard let combined = Data(base64Encoded: b64) else { throw RelayError.bad("格式不對") }
        let box = try ChaChaPoly.SealedBox(combined: combined)
        let plain = try ChaChaPoly.open(box, using: key, authenticating: aad)
        guard let obj = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            throw RelayError.bad("格式不對")
        }
        return (obj, Data(box.nonce))
    }

    // MARK: 金鑰／配對連結

    static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func keyData(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }

    /// talky://pair?v=1&id=…&k=…&n=Mac 名稱&h=主機1,主機2&p=47810（iPhone 相機掃 QR 就會用 Talky 打開）
    static func pairLink(id: String, key: SymmetricKey, name: String, hosts: [String], port: UInt16) -> String {
        var c = URLComponents()
        c.scheme = "talky"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "v", value: "\(version)"), URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "k", value: base64url(keyData(key))), URLQueryItem(name: "n", value: name),
            URLQueryItem(name: "h", value: hosts.joined(separator: ",")), URLQueryItem(name: "p", value: "\(port)"),
        ]
        return c.url?.absoluteString ?? ""
    }

    static func newPairID() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    // MARK: 誰可以連進來

    /// 私有網段／Tailscale／本機／鏈路本地才收
    static func isAllowed(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a):
            let b = [UInt8](a.rawValue)
            guard b.count == 4 else { return false }
            if b[0] == 10 || b[0] == 127 { return true }
            if b[0] == 172 && (16...31).contains(b[1]) { return true }
            if b[0] == 192 && b[1] == 168 { return true }
            if b[0] == 169 && b[1] == 254 { return true }
            if b[0] == 100 && (64...127).contains(b[1]) { return true }  // Tailscale（CGNAT 100.64/10）
            return false
        case .ipv6(let a):
            let b = [UInt8](a.rawValue)
            guard b.count == 16 else { return false }
            if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }  // ::1
            if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }  // fe80::/10
            if (b[0] & 0xFE) == 0xFC { return true }  // fc00::/7（含 Tailscale fd7a:115c:a1e0::/48）
            // IPv4 對應位址（::ffff:a.b.c.d）
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {
                let v4 = IPv4Address(Data(b[12..<16]))
                return v4.map { isAllowed(.hostPort(host: .ipv4($0), port: 0)) } ?? false
            }
            return false
        default:
            return false
        }
    }

    // MARK: 最小 HTTP/1.1（只收 POST＋Content-Length）

    struct Request {
        let method: String
        let path: String
        let body: Data
    }

    /// 還沒收完回 nil；收完回 Request；壞掉丟錯
    static func parse(_ buf: Data) throws -> Request? {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else {
            if buf.count > 8192 { throw RelayError.bad("標頭太大") }
            return nil
        }
        guard let head = String(data: buf[..<end.lowerBound], encoding: .utf8) else { throw RelayError.bad("標頭壞了") }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ").map(String.init) ?? []
        guard first.count >= 2 else { throw RelayError.bad("請求壞了") }
        var length = 0
        for l in lines.dropFirst() {
            let kv = l.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "content-length" { length = Int(kv[1]) ?? 0 }
        }
        if length > 64 * 1024 { throw RelayError.tooBig }
        let bodyStart = end.upperBound
        guard buf.count - bodyStart >= length else { return nil }
        return Request(method: first[0], path: first[1], body: Data(buf[bodyStart..<(bodyStart + length)]))
    }

    static func response(_ status: Int, _ obj: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 413: "Too Large", 429: "Too Many"][status] ?? "Error"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    // MARK: 重放與頻率

    final class Guardrail {
        private var nonces: [Data] = []
        private var nonceSet = Set<Data>()
        private var hits: [Date] = []
        private let lock = NSLock()

        /// 時間戳要在 ±120 秒內、nonce 沒見過
        func accept(ts: Double, nonce: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard abs(Date().timeIntervalSince1970 - ts) < 120, !nonceSet.contains(nonce) else { return false }
            nonces.append(nonce)
            nonceSet.insert(nonce)
            if nonces.count > 1024 { nonceSet.remove(nonces.removeFirst()) }
            return true
        }

        /// 每分鐘最多 limit 次
        func allow(limit: Int = 60) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let now = Date()
            hits = hits.filter { now.timeIntervalSince($0) < 60 }
            guard hits.count < limit else { return false }
            hits.append(now)
            return true
        }
    }

    // MARK: 這台 Mac 的位址（放進 QR 碼；iPhone 依序試）

    /// <本機名稱>.local、區網 IPv4、Tailscale IPv4（100.x）
    static func hosts() -> [String] {
        var out: [String] = []
        if let local = ProcessInfo.processInfo.hostName.split(separator: ".").first, !local.isEmpty {
            out.append("\(local).local")
        }
        var lan: [String] = []
        var ts: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let first = ifaddr {
            var p: UnsafeMutablePointer<ifaddrs>? = first
            while let cur = p {
                let flags = Int32(cur.pointee.ifa_flags)
                if let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                    (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0
                {
                    var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostBuf)
                        if ip.hasPrefix("100."), let second = Int(ip.split(separator: ".")[1]), (64...127).contains(second) {
                            ts.append(ip)
                        } else if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                            lan.append(ip)
                        }
                    }
                }
                p = cur.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return out + lan + ts
    }
}

enum RelayError: LocalizedError {
    case bad(String)
    case tooBig
    var errorDescription: String? {
        switch self {
        case .bad(let s): return s
        case .tooBig: return "內容太大"
        }
    }
}
