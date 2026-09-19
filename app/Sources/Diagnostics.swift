// Diagnostics — 一份看得懂的體檢：--doctor 印在終端機、設定頁「匯出診斷檔」寫到桌面
//
// 給回報問題的人用：出問題時把桌面那份 txt 傳回來，不用自己翻記錄檔。
// 內容：權限／模型／引擎／整理模式／同一家會議 app 的狀態／設定（金鑰永不列）／系統／記錄檔最後 300 行。

import AVFoundation
import AppKit
import Foundation

enum Diagnostics {
    static func report() -> String {
        var out: [String] = ["Talky doctor"]
        func line(_ ok: Bool, _ name: String, _ detail: String = "") {
            out.append("  \(ok ? "ok  " : "缺  ") \(name)\(detail.isEmpty ? "" : "：" + detail)")
        }
        // 權限：app 在跑就用它回報的（從終端機跑 doctor，TCC 會把麥克風／輔助使用算到終端機頭上，
        // 自己問到的答案可能是終端機的；病史＝doctor 說已授權、app 其實沒有）
        let running = appRunning
        let report = listenerReport()
        let micOwn = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axOwn = Dictation.axTrusted
        let mic = report?.mic ?? micOwn
        let ax = report?.ax ?? axOwn
        let src = isGUI ? "" : (report != nil ? "（app 回報）" : "（doctor 自己問的：從終端機跑時可能反映終端機的權限，以狀態視窗為準）")
        line(mic, "麥克風", (mic ? "已允許" : "沒允許") + src)
        line(ax, "輔助使用", (ax ? "已授權" : "未授權：連按右 ⌘ 不會有反應。系統設定 → 隱私權與安全性 → 輔助使用 → Talky 打開") + src)
        // 快捷鍵在不在聽：這支 doctor 是另一個行程，看不到 app 的記憶體，靠 app 每 1.5 秒回寫的 defaults
        line(running, "Talky 在跑", running ? (isGUI ? "是（這份是從 app 裡匯出的）" : "是") : "沒有（要開著它，快捷鍵才會聽）")
        let trig = Dictation.trigger.longLabel
        let hk: (Bool, String)
        if !running {
            hk = (false, "Talky 沒在跑")
        } else if !ax {
            hk = (false, "不會動：先開輔助使用（開完 2 秒內自動接上）")
        } else if let r = report {
            hk = r.ok
                ? (true, isGUI ? "在聽（\(trig)）" : "在聽（\(trig)；app \(r.age) 秒前回報）")
                : (false, "沒接上（app \(r.age) 秒前回報）：系統設定 → 隱私權與安全性 → 輸入監控 → Talky 打開")
        } else {
            hk = (false, "app 還沒回報（剛開？等 2 秒再跑一次；0.1.0 版沒有這行）")
        }
        line(hk.0, "快捷鍵", hk.1)
        line(TextUtil.whisperModelPath() != nil, "語音模型", TextUtil.whisperModelPath() ?? "未下載")
        line(LocalLLM.modelPath() != nil, "整理模型", LocalLLM.modelPath() ?? "未下載（走 Claude Code 就不需要）")
        let cst = ClaudeCLI.available ? ClaudeCLI.authStatus() : nil
        line(
            cst?.loggedIn == true, "Claude Code",
            !ClaudeCLI.available
                ? "找不到 claude 指令（設定 → 進階 → Claude 那列按「安裝」）"
                : "\(ClaudeCLI.binaryPath() ?? "")（\(cst?.loggedIn == true ? "已登入 \(cst!.subscriptionLabel)，模型 \(ClaudeCLI.model)" : "未登入：設定 → 進階 → Claude 那列按「登入」，在 app 裡完成")）")
        line(
            CodexCLI.available, "ChatGPT（Codex）",
            CodexCLI.available
                ? "\(CodexCLI.binaryPath() ?? "")（\(CodexCLI.loggedIn() == true ? "已登入" : "未登入")）"
                : "找不到 codex（裝 ChatGPT 桌面版就有）")
        line(Endpoints.openAIFilled, "自填 OpenAI 相容端點",
            Endpoints.openAIFilled ? "\(Endpoints.openAIModel) @ \(Endpoints.host(Endpoints.openAIBase))" : "未填")
        line(Endpoints.anthropicFilled, "自填 Anthropic 金鑰",
            Endpoints.anthropicFilled ? "\(Endpoints.anthropicModel) @ \(Endpoints.host(Endpoints.anthropicBase))" : "未填")
        out.append("  ——  整理模式：\(PolishMode.current.rawValue)")
        let w = TalkyServers.shared.alive(port: TalkyServers.whisperPort, path: "/", timeout: 1)
        let l = TalkyServers.shared.alive(port: TalkyServers.llamaPort, path: "/health", timeout: 1)
        line(w, "語音引擎 port \(TalkyServers.whisperPort)", w ? "有回應" : "沒有回應（app 沒開就是正常的）")
        line(l, "整理引擎 port \(TalkyServers.llamaPort)", l ? "有回應" : "沒有回應（走 Claude Code 就是正常的）")
        out.append("  ——  記錄檔：\(SharedPaths.logDir.path)")
        out.append("  ——  資料夾：\(SharedPaths.support.path)")
        if let s = SharedPaths.siblingSupport {
            out.append("  ——  借用中的既有模型／常用詞資料夾：\(s.path)")
        }
        if SharedPaths.siblingAppRunning {
            let on = SharedPaths.siblingIMEEnabled
            line(
                !on, "Hearby 搶鍵",
                on ? "它在跑而且輸入法開著，會跟右 ⌘ 搶：狀態視窗或精靈第 4 步按「關掉它的輸入法」" : "它在跑，輸入法已關，不會搶")
        }
        return out.joined(separator: "\n")
    }

    /// 自己就是 GUI app（設定頁「匯出診斷檔」那條路）：NSApp 在 --doctor 的 CLI 路上是 nil
    static var isGUI: Bool { NSApp != nil }

    /// Talky（GUI）在不在跑：自己就是 GUI 時當然在跑；否則找這個 bundle 的另一個行程。
    /// 病史：以前一律排除自己的 pid，從 app 內匯出就寫「Talky 在跑：沒有／快捷鍵：沒在跑」，
    /// 三行紅字全是誤報，權限也退成「doctor 自己問的」。
    static var appRunning: Bool {
        if isGUI { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        let bid = Bundle.main.bundleIdentifier ?? "ltd.intention.talky"
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bid && $0.processIdentifier != me
        }
    }

    /// app 每 1.5 秒回寫的權限與監聽狀態；app 沒在跑或超過 30 秒沒回報視為沒資料。
    /// 自己就是 GUI 時直接讀活的值（不用繞 defaults）。
    static func listenerReport() -> (ok: Bool, ax: Bool, mic: Bool, age: Int)? {
        if isGUI {
            return (
                DictationController.shared.hotkeyActive, Dictation.axTrusted,
                AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, 0)
        }
        guard appRunning else { return nil }
        let d = UserDefaults.standard
        guard d.object(forKey: "hotkeyListenerOK") != nil, d.object(forKey: "axTrustedReported") != nil else { return nil }
        let at = d.double(forKey: "hotkeyListenerAt")
        let age = Date().timeIntervalSince1970 - at
        guard at > 0, age < 30 else { return nil }
        return (
            d.bool(forKey: "hotkeyListenerOK"), d.bool(forKey: "axTrustedReported"), d.bool(forKey: "micGrantedReported"),
            Int(age))
    }

    /// 寫到桌面：Talky診斷_YYYYMMDD-HHmm.txt。回傳檔案位置；失敗回 nil（原因進記錄檔）。
    static func export() -> URL? {
        var s = report()
        s += "\n\n── 設定（金鑰永不列）──\n"
        let keys = [
            "polishMode", "hotkeyTrigger", "pasteMode", "appearance", "statusLight", "onboardingDone",
            "ollamaModel", "ollamaResolvedModel", "openaiBase", "openaiModel", "anthropicBase", "anthropicModel",
            "claudeModel", "claudeEffort", "claudeTimeout", "imeLite", "hotkeyListenerOK", "axTrustedReported", "micGrantedReported",
        ]
        let d = UserDefaults.standard
        for k in keys {
            if let v = d.object(forKey: k) { s += "  \(k) = \(v)\n" }
        }
        let info = Bundle.main.infoDictionary ?? [:]
        s += "\n── 系統 ──\n"
        s += "  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)；記憶體 \(Dictation.physicalMemoryGB)GB；"
        s += "app \(info["CFBundleShortVersionString"] ?? "?") build \(info["CFBundleVersion"] ?? "?")\n"
        s += "\n── 記錄檔最後 300 行 ──\n"
        let logFile = SharedPaths.logDir.appendingPathComponent("talky.log")
        if let log = try? String(contentsOf: logFile, encoding: .utf8) {
            s += log.split(separator: "\n").suffix(300).joined(separator: "\n")
        } else {
            s += "（沒有記錄檔）"
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Talky診斷_\(f.string(from: Date())).txt")
        do {
            try s.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            TalkyLog.write("diagnostics export fail: \(error)")
            return nil
        }
    }
}
