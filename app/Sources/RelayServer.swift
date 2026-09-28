// RelayServer — 讓 iPhone 版 Talky 用這台 Mac 的大腦（Claude Code／ChatGPT 的 Codex 訂閱）整理與翻譯
//
// 目的：讓人用自己的 AI 訂閱（Claude、ChatGPT）整理 iPhone 上的口述、不用 API 金鑰 → 做法是「經由自己的 Mac」。
// iPhone 不碰任何帳號：登入永遠在這台 Mac 上、走 Anthropic／OpenAI 自己的登入頁（ClaudeLogin／CodexLogin），
// 跑的是沒改過的官方 CLI；iPhone 只把一句話（加密）送過來，這裡照 Mac 自己選的大腦跑完再加密送回。
// 預設關（設定 → iPhone 打開）；底層安全規則見 RelayCore.swift。
//
// 請求（解密後）：{"op": "polish"|"translate"|"status"|"login", "ts": 秒, "text", "to", "guide", "speaker", "glossary", "brain": "claude"|"codex"|""}
// 翻譯的 prompt 跟 INTENTION 內網 /api/talky/polish 那份一字不差（iPhone 兩條路給一樣的結果）。

import AppKit
import CoreImage
import CryptoKit
import Foundation
import Network
import SwiftUI

final class RelayServer: ObservableObject {
    static let shared = RelayServer()
    static let port: UInt16 = 47810

    @Published private(set) var running = false
    @Published private(set) var lastUse: Date?
    @Published private(set) var todayCount = 0
    @Published private(set) var note = ""
    @Published private(set) var link = ""

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ltd.intention.talky.relay")
    private let guardrail = RelayCore.Guardrail()

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "relayEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "relayEnabled") }
    }

    // MARK: 開關

    func startIfEnabled() {
        if Self.enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        Self.enabled = on
        on ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] st in
                DispatchQueue.main.async {
                    switch st {
                    case .ready:
                        self?.running = true
                        self?.note = ""
                        TalkyLog.write("relay 開始聽 :\(Self.port)")
                    case .failed(let e):
                        self?.running = false
                        self?.note = "開不起來：\(e.localizedDescription)（埠 \(Self.port) 被別的程式占用？）"
                        self?.listener?.cancel()
                        self?.listener = nil
                        TalkyLog.write("relay 失敗 \(e)")
                    case .cancelled:
                        self?.running = false
                    default:
                        break
                    }
                }
            }
            listener = l
            l.start(queue: queue)
            refreshLink()
        } catch {
            note = "開不起來：\(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
        TalkyLog.write("relay 關掉")
    }

    // MARK: 配對（金鑰放鑰匙圈；換一組＝舊 iPhone 失效）

    private var pairID: String {
        if let id = UserDefaults.standard.string(forKey: "relayPairID"), !id.isEmpty { return id }
        let id = RelayCore.newPairID()
        UserDefaults.standard.set(id, forKey: "relayPairID")
        return id
    }

    private var cachedKey: SymmetricKey?
    private var key: SymmetricKey {
        if let k = cachedKey { return k }
        if let d = RelayKeychain.load(), d.count == 32 {
            cachedKey = SymmetricKey(data: d)
        } else {
            let k = RelayCore.newKey()
            RelayKeychain.save(RelayCore.keyData(k))
            cachedKey = k
        }
        return cachedKey!
    }

    func regenerate() {
        UserDefaults.standard.set(RelayCore.newPairID(), forKey: "relayPairID")
        let k = RelayCore.newKey()
        RelayKeychain.save(RelayCore.keyData(k))
        cachedKey = k
        refreshLink()
        TalkyLog.write("relay 換配對碼")
    }

    func refreshLink() {
        let name = Host.current().localizedName ?? "Mac"
        link = RelayCore.pairLink(id: pairID, key: key, name: name, hosts: RelayCore.hosts(), port: Self.port)
    }

    // MARK: 連線

    /// 一條連線收完請求沒（收完就不要被 10 秒計時器斷掉：大腦可能要跑 20 秒）
    private final class Received { var done = false }

    private func accept(_ c: NWConnection) {
        guard RelayCore.isAllowed(c.endpoint) else {
            c.cancel()
            return
        }
        let got = Received()
        c.start(queue: queue)
        // 10 秒內沒送完請求就斷（慢速攻擊）
        queue.asyncAfter(deadline: .now() + 10) { [weak c] in
            if let c, !got.done { c.cancel() }
        }
        receive(c, Data(), got)
    }

    private func receive(_ c: NWConnection, _ buffer: Data, _ got: Received) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            do {
                if let req = try RelayCore.parse(buf) {
                    got.done = true
                    self.handle(req, c)
                    return
                }
            } catch RelayError.tooBig {
                self.send(c, 413, ["error": "內容太大"])
                return
            } catch {
                self.send(c, 400, ["error": "請求壞了"])
                return
            }
            if done || err != nil {
                c.cancel()
                return
            }
            self.receive(c, buf, got)
        }
    }

    private func send(_ c: NWConnection, _ status: Int, _ obj: [String: Any]) {
        c.send(content: RelayCore.response(status, obj), completion: .contentProcessed { _ in c.cancel() })
    }

    private func handle(_ req: RelayCore.Request, _ c: NWConnection) {
        guard req.method == "POST", req.path == RelayCore.path else {
            send(c, 404, ["error": "沒有這個"])
            return
        }
        guard guardrail.allow() else {
            send(c, 429, ["error": "太頻繁，等一下再試"])
            return
        }
        let id = pairID
        let k = key
        guard let env = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any],
            env["id"] as? String == id, let b = env["b"] as? String,
            let (msg, nonce) = try? RelayCore.open(b, key: k, aad: RelayCore.requestAAD(id)),
            let ts = msg["ts"] as? Double, guardrail.accept(ts: ts, nonce: nonce)
        else {
            TalkyLog.write("relay 拒絕：配對碼不對或過期")
            send(c, 403, ["error": "配對碼不對：到 Mac 版 Talky → 設定 → iPhone 重掃一次 QR 碼"])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let out = self.run(msg)
            guard let sealed = try? RelayCore.seal(out, key: k, aad: RelayCore.responseAAD(id)) else {
                self.send(c, 400, ["error": "回不了"])
                return
            }
            self.send(c, 200, ["b": sealed])
        }
    }

    // MARK: 做事

    private func run(_ msg: [String: Any]) -> [String: Any] {
        let op = msg["op"] as? String ?? ""
        switch op {
        case "status":
            return status()
        case "login":
            let provider = msg["provider"] as? String ?? ""
            DispatchQueue.main.async {
                if provider == "codex" {
                    // iPhone 叫的登入不換 Mac 自己的整理大腦
                    if !CodexLogin.shared.start(bind: false) { self.note = "這台還沒有 Codex：裝 ChatGPT 桌面版或 Codex CLI" }
                } else {
                    if !ClaudeLogin.shared.start() { self.note = "這台還沒有 Claude Code：到 設定 → 用什麼來整理 安裝" }
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            return ["ok": true, "note": "Mac 上已經打開登入頁：在 Mac 上完成登入"]
        case "polish", "translate":
            let text = String((msg["text"] as? String ?? "").prefix(4000))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ["ok": false, "error": "沒有字"] }
            let brain = msg["brain"] as? String ?? ""
            let t0 = Date()
            if op == "polish" {
                let (out, err, used) = runTask(TalkyServers.polishTask, raw: text, brain: brain)
                record("polish", text.count, out?.count ?? 0, t0, used)
                guard let out, !out.isEmpty else { return ["ok": false, "error": err ?? "沒有結果"] }
                return ["ok": true, "text": out, "brain": used]
            }
            let to = msg["to"] as? String ?? ""
            guard let task = RelayPrompts.translateTask(
                to: to, guide: String((msg["guide"] as? String ?? "").prefix(600)),
                speaker: msg["speaker"] as? String ?? "",
                glossary: (msg["glossary"] as? [String] ?? []).prefix(60).map { String($0.prefix(40)) })
            else { return ["ok": false, "error": "不支援這個語言"] }
            let (out, err, used) = runTask(task, raw: text, brain: brain)
            guard let out, !out.isEmpty else {
                record("translate", text.count, 0, t0, used)
                return ["ok": false, "error": err ?? "沒有結果"]
            }
            let (tr, back, zh) = RelayPrompts.parseTranslation(out)
            record("translate→\(to)", text.count, tr.count, t0, used)
            return ["ok": true, "text": tr, "back": back, "zh": zh, "brain": used]
        default:
            return ["ok": false, "error": "不認得的請求"]
        }
    }

    /// iPhone 指定 claude／codex 就只用那顆（不退路，失敗照實回，iPhone 自己有退路）；沒指定＝照 Mac 的設定走整條路由
    private func runTask(_ task: LLMTask, raw: String, brain: String) -> (String?, String?, String) {
        if brain == "claude", ClaudeCLI.available {
            let (o, e) = TalkyServers.shared.polishVia(.claude, raw: raw, task: task)
            return (o, e, "claude")
        }
        if brain == "codex", CodexCLI.available {
            let (o, e) = TalkyServers.shared.polishVia(.codex, raw: raw, task: task)
            return (o, e, "codex")
        }
        let r = TalkyServers.shared.routed(task: task, raw: raw)
        return (r.text, r.err, r.path.rawValue)
    }

    private func status() -> [String: Any] {
        let claude: Any = ClaudeCLI.available ? ClaudeCLI.loggedInNow : NSNull()
        let codex: Any = CodexCLI.available ? (CodexCLI.loggedIn() ?? false) : NSNull()
        return [
            "ok": true, "v": RelayCore.version, "name": Host.current().localizedName ?? "Mac",
            "brain": PolishMode.current.rawValue, "claude": claude, "codex": codex,
        ]
    }

    /// 只記字數與秒數，不記內容
    private func record(_ what: String, _ inCount: Int, _ outCount: Int, _ t0: Date, _ brain: String) {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        TalkyLog.write("relay \(what) \(inCount)→\(outCount) 字 \(ms)ms \(brain)")
        DispatchQueue.main.async {
            if let last = self.lastUse, Calendar.current.isDateInToday(last) {
                self.todayCount += 1
            } else {
                self.todayCount = 1
            }
            self.lastUse = Date()
        }
    }
}

/// 配對金鑰放鑰匙圈（登入鑰匙圈，只有這台 Mac 的 Talky 讀得到）
enum RelayKeychain {
    private static let service = "ltd.intention.talky.relay"
    private static let account = "pairing-key"

    static func load() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func save(_ data: Data) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - 設定頁那一段

struct RelaySettingsView: View {
    @ObservedObject private var relay = RelayServer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.md) {
            HStack(spacing: NeuSpace.md) {
                NeuStatusTag(level: relay.running ? .ready : .missing, text: relay.running ? "開著：iPhone 可以連過來" : "關著")
                Spacer()
                NeuChip(title: relay.running ? "關掉" : "打開") { relay.setEnabled(!relay.running) }
            }
            if relay.running {
                HStack(alignment: .top, spacing: NeuSpace.lg) {
                    QRCodeImage(text: relay.link)
                        .frame(width: 150, height: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    VStack(alignment: .leading, spacing: NeuSpace.sm) {
                        Text("用 iPhone 相機掃這個碼，Talky 會自動配對")
                            .font(NeuFont.ui(NeuType.caption, true)).foregroundColor(Neu.inkStrong)
                        NeuNote(text: "iPhone 整理與翻譯會用這台 Mac 現在選的大腦（Claude Code 或 ChatGPT 的 Codex 訂閱）。只在同一個網路或 Tailscale 裡通；內容用配對金鑰加密，不經過任何第三方。")
                        if let last = relay.lastUse {
                            Text("上次 iPhone 用：\(Self.time.string(from: last))・今天 \(relay.todayCount) 句")
                                .font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                        }
                        NeuChip(title: "換一組配對碼（舊的 iPhone 要重掃）") { relay.regenerate() }
                    }
                }
            } else {
                NeuNote(text: "打開後，iPhone 版 Talky 可以用這台 Mac 登入的 Claude Code／ChatGPT（Codex）訂閱整理與翻譯，不用 API 金鑰。預設關；只接同一個網路或 Tailscale 裡、掃過 QR 碼的 iPhone。")
            }
            if !relay.note.isEmpty {
                Text(relay.note).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
            }
        }
        .onAppear { if relay.running { relay.refreshLink() } }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// QR 碼（CoreImage 產生，放大不糊）
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let img = Self.make(text) {
            Image(nsImage: img).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.white
        }
    }

    static func make(_ s: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(s.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
