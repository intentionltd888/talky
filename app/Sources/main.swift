// Talky — Mac 上的繁體中文語音輸入法
//
// 任何文字框連按兩下右⌘講話，邊講邊出字，再按一次就把整理好的書面繁中貼進游標。
// 整理預設用你自己的 Claude Code；沒有就用本機模型；都沒有也照樣貼原稿。
//
// app 形態：Dock 常駐（點圖示開狀態視窗）＋選單列一顆狀態燈（可在設定關）。
// 通知只在「引擎就緒」時跳一則；出錯一律顯示在浮動面板上，不發通知。
//
// 命令列（不開 UI）：
//   Talky --ime-polish "<一句口述>" [更多句…]   跑整理路由並印出結果（接線測試用）
//   Talky --doctor                              印出麥克風／輔助使用／模型／CLI／port 狀態
//   Talky --autopick                            跑一次精靈的自動選整理方式並印結果（測試鉤）
//   Talky --ime-translate ja <一句口述>         跑翻譯路由並印出譯文與守門結果（接線測試用）
//   Talky --claude-install                      跑一次 app 內安裝 Claude Code 並印過程（測試鉤）

import AVFoundation
import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

signal(SIGPIPE, SIG_IGN)  // 子進程早退時寫 pipe 不炸整個 app

let cliArgs = CommandLine.arguments

// ── CLI：--ime-translate <語言代碼> <句子…> ──────────────────
// 翻譯路由接線測試：印出走哪條、幾秒、譯文、以及字元集守門有沒有過（en ja ko th vi id es fr de pt zhHans yue）
if let idx = cliArgs.firstIndex(of: "--ime-translate"), idx + 2 < cliArgs.count {
    guard let target = TranslateTarget(rawValue: cliArgs[idx + 1]) else {
        print("不認得的語言：\(cliArgs[idx + 1])；可用：\(TranslateTarget.allCases.map(\.rawValue).joined(separator: " "))")
        exit(2)
    }
    print("mode=\(PolishMode.current.rawValue) target=\(target.rawValue) audience=\(Translate.audience.rawValue) gender=\(Translate.gender.rawValue)")
    for raw in cliArgs[(idx + 2)...] {
        let t0 = Date()
        let r = TalkyServers.shared.translateRouted(raw: raw, target: target)
        let text = r.text ?? ""
        let ok = !text.isEmpty && target.looksLike(text)
        print(String(format: "%@ %.1fs path=%@ ", ok ? "OK" : "FAIL", Date().timeIntervalSince(t0), r.path.rawValue) + (text.isEmpty ? "（空）" : text))
        if let e = r.err { FileHandle.standardError.write("  （\(e)）\n".data(using: .utf8)!) }
    }
    ClaudeCLI.shutdownWarm()
    TalkyServers.shared.shutdownForQuit()
    exit(0)
}

// ── CLI：--ime-polish ───────────────────────────────────────
// 後面每個參數都是一句口述：同一進程連跑，第 2 句起走暖會話。
// 三條路（Claude Code／本機模型／原稿）都算成功，但會印出實際走了哪一條。
if let idx = cliArgs.firstIndex(of: "--ime-polish"), idx + 1 < cliArgs.count {
    print(
        "mode=\(PolishMode.current.rawValue) lite=\(Dictation.lite) claude=\(ClaudeCLI.binaryPath() ?? "-") model=\(ClaudeCLI.model)"
    )
    for raw in cliArgs[(idx + 1)...] {
        let t0 = Date()
        let r = TalkyServers.shared.polishRouted(raw: raw)
        let text = (r.text?.isEmpty == false) ? r.text! : raw
        let out = TextUtil.normalizePunct(TextUtil.toTraditional(text))
        print(String(format: "OK %.1fs path=%@ ", Date().timeIntervalSince(t0), r.path.rawValue) + out)
        if let e = r.err {
            FileHandle.standardError.write("  （\(r.path.label)：\(e)）\n".data(using: .utf8)!)
        }
    }
    ClaudeCLI.shutdownWarm()
    TalkyServers.shared.shutdownForQuit()  // 退路可能臨時拉了 llama，走了要收
    exit(0)
}

// ── CLI：--autopick（測試鉤：跑一次精靈的自動選，印選了哪顆；不動 UI）──
if cliArgs.contains("--autopick") {
    let k = Brains.autoPick()
    print("autopick → \(k.rawValue)  reason: \(Brains.pickReason(k))  polishMode(defaults)=\(UserDefaults.standard.string(forKey: "polishMode") ?? "nil")")
    exit(0)
}

// ── CLI：--claude-install（測試鉤：跑一次 app 內安裝 Claude Code，印過程；defaults claudeInstallCommand 可換成假指令）──
if cliArgs.contains("--claude-install") {
    let inst = ClaudeInstall.shared
    guard inst.start() else { print("spawn fail"); exit(2) }
    var last = ""
    while inst.running {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if inst.note != last { print(inst.note); last = inst.note }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    print(inst.note)
    print("succeeded=\(inst.succeeded) failed=\(inst.failed) claude=\(ClaudeCLI.binaryPath() ?? "nil")")
    ClaudeLogin.shared.cancel()
    exit(inst.succeeded ? 0 : 1)
}

// ── CLI：--codex-setup（測試鉤：沒 codex 就 app 內下載、有就 app 內登入；印過程；最多等 --codex-secs 秒，預設 40）──
if cliArgs.contains("--codex-setup") {
    let secs = cliArgs.firstIndex(of: "--codex-secs").flatMap { $0 + 1 < cliArgs.count ? Double(cliArgs[$0 + 1]) : nil } ?? 40
    let inst = CodexInstall.shared
    let login = CodexLogin.shared
    if CodexCLI.available, !cliArgs.contains("--force-install") {
        // 病史：已登入還跑 `codex login` 會先把現有登入清掉（auth.json 直接消失）
        if CodexCLI.loggedIn(force: true) == true, !cliArgs.contains("--force-login") {
            print("codex 已登入，不重跑登入（要強制：--force-login）")
            exit(0)
        }
        print("codex 已在：\(CodexCLI.binaryPath() ?? "?")，直接登入")
        guard login.start() else { print("login spawn fail"); exit(2) }
    } else {
        guard inst.start() else { print("install spawn fail"); exit(2) }
    }
    var last = ""
    let deadline = Date().addingTimeInterval(secs)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let n = inst.running || inst.failed ? inst.note : login.note
        if n != last { print(n); last = n }
        if login.succeeded || inst.failed { break }
        if !inst.running && !login.running && !inst.succeeded { break }
    }
    print("install: running=\(inst.running) ok=\(inst.succeeded) fail=\(inst.failed) | login: running=\(login.running) ok=\(login.succeeded) url=\(login.url ?? "-")")
    print("codex=\(CodexCLI.binaryPath() ?? "nil") loggedIn=\(CodexCLI.loggedIn(force: true).map { String($0) } ?? "nil") polishMode=\(PolishMode.current.rawValue)")
    login.cancel()
    inst.cancel()
    exit(login.succeeded ? 0 : 1)
}

// ── CLI：--doctor ──────────────────────────────────────────
if cliArgs.contains("--doctor") {
    print(Diagnostics.report())
    exit(0)
}

// ── CLI：--caption-demo ────────────────────────────────────
// 不收音、不辨識，只把浮動面板六態各停 2.5 秒輪一遍（設計審查與截圖用），跑完自動退出。
let captionDemo = cliArgs.contains("--caption-demo")

// ── 選單列狀態燈 ────────────────────────────────────────────

/// 三態（圖標板 13 號稿）：就緒＝空心米字／聽寫中＝實心／有問題＝實心＋右下一點；啟動中＝空心淡。
/// 跟 app 內 TalkyMarkShape 同一套幾何，程式畫，template 圖跟選單列深淺走。
func statusSymbol() -> NSImage? {
    let health = AppState.shared.health
    let size: CGFloat = 18
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let r = size * 0.40
        let w = r * 0.42
        let mark = NSBezierPath()
        for k in 0..<3 {
            let t = NSAffineTransform()
            t.translateX(by: c.x, yBy: c.y)
            t.rotate(byDegrees: CGFloat(k) * 60)
            let bar = NSBezierPath(
                roundedRect: NSRect(x: -w / 2, y: -r, width: w, height: 2 * r), xRadius: w / 2, yRadius: w / 2)
            bar.transform(using: t as AffineTransform)
            mark.append(bar)
        }
        switch health {
        case .dictating:
            NSColor.black.setFill()
            mark.fill()
        case .ready:
            NSColor.black.setStroke()
            mark.lineWidth = 1.1
            mark.stroke()
        case .starting:
            NSColor.black.withAlphaComponent(0.45).setStroke()
            mark.lineWidth = 1.1
            mark.stroke()
        case .needsSetup, .broken:
            NSColor.black.setFill()
            mark.fill()
            NSBezierPath(ovalIn: NSRect(x: size - 5, y: 0, width: 4.5, height: 4.5)).fill()
        }
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "Talky"
    return img
}

// ── App ─────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var statusWindow: NSWindow?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    private var readyNotified = false
    private var tick: Timer?
    /// App Nap 阻斷票（實測，這是本包最貴的一個坑）：
    /// 輸入法在**真正被用到的時候永遠是背景 app**（你在別的 app 裡打字），
    /// 而 macOS 的 App Nap 專門掐這種「背景、視窗被遮住」的 app——連它 spawn 的子行程一起降速。
    /// 同一句潤飾：前景／終端機 2.4 秒，被 App Nap 掐住的背景 app 31.9 秒。
    /// 用 .userInitiatedAllowingIdleSystemSleep：擋掉 App Nap，但不阻止電腦正常進入睡眠。
    private var antiNap: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 從磁碟映像直接雙擊＝自己裝（0.1.8）：問一次 → 複製到 /Applications → 釘 Dock → 從那裡重開。
        // 以前是擋下來教他拖（權限會綁到唯讀掛載路徑）；現在拖與雙擊都通。`--install`＝不問直接裝（測試鉤）。
        if Installer.isRunningFromDiskImage {
            Installer.offerInstallFromDiskImage(autoYes: cliArgs.contains("--install"))
            return
        }
        TalkyLog.write("launch build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        // 從 DMG 自己裝完重開會帶 --eject <掛載點>：把磁碟映像退出，桌面不留那顆
        if let i = cliArgs.firstIndex(of: "--eject"), i + 1 < cliArgs.count { Installer.ejectLater(cliArgs[i + 1]) }
        // 第一次從 /Applications 啟動＝釘進 Dock（只做一次；自己拖進去的人也會有）
        if Installer.isRunningFromApplications, !UserDefaults.standard.bool(forKey: "dockPinned") {
            UserDefaults.standard.set(true, forKey: "dockPinned")
            Dock.ensure(appURL: Installer.installedURL)
        }
        antiNap = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "語音輸入法要在背景即時回應")
        ModelCatalog.loadCached()

        if Dictation.showStatusLight { installStatusItem() }
        NotificationCenter.default.addObserver(
            forName: .talkyStatusLightChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if Dictation.showStatusLight {
                self.installStatusItem()
            } else {
                if let s = self.statusItem { NSStatusBar.system.removeStatusItem(s) }
                self.statusItem = nil
            }
        }

        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.setNotificationCategories([
                UNNotificationCategory(
                    identifier: "ready",
                    actions: [
                        UNNotificationAction(
                            identifier: "try", title: "試講一句", options: [.foreground])
                    ],
                    intentIdentifiers: [], options: [])
            ])
        }

        DictationController.shared.onStateChange = { [weak self] in
            AppState.shared.refresh()
            self?.refreshStatusIcon()
        }
        DictationController.shared.syncWithSettings()

        // 引擎預熱：就緒後跳一則通知（只跳這一則）。
        // QoS 必須 .userInitiated：子行程繼承 spawn 執行緒的 QoS，用 .utility 起的引擎
        // 會被綁在節能核心上被節流，而且那顆 QoS 跟著行程一輩子（見 ClaudeCLI 的實測註解）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            TalkyServers.reapOrphanEngines()  // 上一個 Talky 閃退／被 kill 留下的引擎先收掉
            let err = TalkyServers.shared.startAll()
            if PolishMode.current == .ollama { Ollama.warm() }  // 第一句不用等模型冷載
            DispatchQueue.main.async {
                AppState.shared.refresh()
                self?.refreshStatusIcon()
                if err == nil { self?.notifyReadyOnce() }
            }
        }

        tick = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshStatusIcon()
        }

        if captionDemo {
            runCaptionDemo()
            return
        }
        // --panel-hold：把翻譯聽態面板掛 25 秒（不收音），印出每顆語言籤的螢幕座標與被點的籤——焦點驗收用
        if cliArgs.contains("--panel-hold") {
            setvbuf(stdout, nil, _IONBF, 0)  // 不緩衝：被 kill 也不丟輸出
            print("panel-hold on")
            CaptionDebug.reportChipFrames = true
            let pc = DictationController.shared.panel
            pc.model.onPickTarget = { t in
                print("picked \(t.rawValue)")
                fflush(stdout)
            }
            pc.showListening(mode: .translate, target: .ja)
            pc.update("焦點測試：點籤後鍵盤還在原本的框嗎")
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                TalkyServers.shared.shutdownForQuit()
                exit(0)
            }
            return
        }
        // --demo-text "文字" [--demo-state listen|working|pasted|copied|tr-listen|tr-working|tr-pasted] [--demo-hold 秒] [--demo-lang en|ja|ko|…] [--demo-bg black|white]
        //   [--demo-label "整理中"] [--demo-eta "約 2 秒"]：working 態的標籤與預估秒數（README 的 GIF 用中性字眼）
        // 官網截圖用：把面板掛出來、塞指定文字、印面板框，N 秒後退出。不收音、不辨識。
        if let i = cliArgs.firstIndex(of: "--demo-text"), i + 1 < cliArgs.count {
            setvbuf(stdout, nil, _IONBF, 0)
            let text = cliArgs[i + 1]
            func arg(_ k: String) -> String? { cliArgs.firstIndex(of: k).flatMap { cliArgs.indices.contains($0 + 1) ? cliArgs[$0 + 1] : nil } }
            let state = arg("--demo-state") ?? "listen"
            let hold = arg("--demo-hold").flatMap(Double.init) ?? 10
            let tgt = TranslateTarget(rawValue: arg("--demo-lang") ?? "ja") ?? .ja   // --demo-lang en|ja|ko|th|vi|id|es|fr
            // --demo-bg black|white：面板後面墊一整片純色視窗（去背用：黑白各截一張算 alpha）
            var backdrop: NSWindow? = nil
            if let bg = arg("--demo-bg"), let scr = NSScreen.main {
                let w = NSWindow(contentRect: scr.frame, styleMask: .borderless, backing: .buffered, defer: false)
                w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
                w.backgroundColor = bg == "white" ? .white : .black
                w.isOpaque = true; w.ignoresMouseEvents = true; w.hasShadow = false
                w.orderFrontRegardless(); backdrop = w
            }
            let pc = DictationController.shared.panel
            switch state {
            case "working": pc.showListening(); pc.update(text); pc.working(arg("--demo-label") ?? "整理中，用你的 Claude Code", eta: arg("--demo-eta") ?? "約 2 秒")
            case "pasted": pc.showListening(); pc.update(text); pc.pasted()
            case "copied": pc.showListening(); pc.update(text); pc.copied()
            case "tr-listen": pc.showListening(mode: .translate, target: tgt); pc.update(text); pc.level(0.55)
            case "tr-working": pc.showListening(mode: .translate, target: tgt); pc.update(text); pc.working(arg("--demo-label") ?? "翻成日文中，用你的 Claude Code", eta: arg("--demo-eta") ?? "約 2 秒")
            case "tr-pasted": pc.showListening(mode: .translate, target: tgt); pc.update(text); pc.pasted("已貼上日文")
            default: pc.showListening(); pc.update(text); pc.level(0.5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let (f, s) = pc.debugFrames { print("panel-frame \(NSStringFromRect(f)) screen \(NSStringFromRect(s))") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                backdrop?.orderOut(nil)
                TalkyServers.shared.shutdownForQuit()
                exit(0)
            }
            return
        }
        // --open wizard｜status｜settings[:分頁]：直接開某個視窗（設計審查與截圖用）
        if let i = cliArgs.firstIndex(of: "--open"), i + 1 < cliArgs.count {
            let what = cliArgs[i + 1]
            if what.hasPrefix("wizard") {
                // wizard:N 直接跳第 N 步（0 歡迎…5 好了）
                let n = what.split(separator: ":").count > 1 ? Int(what.split(separator: ":")[1]) : nil
                showOnboarding(startAt: n)
                return
            }
            if what == "status" { showStatusWindow(); return }
            if what.hasPrefix("settings") {
                showSettingsWindow(tab: what.hasSuffix(":1") ? 1 : 0)
                return
            }
        }
        // 第一次開：進五步精靈（0.1.2；原七步見 Onboarding.swift 頭註）；跑完才是狀態視窗
        if Dictation.onboardingDone { showStatusWindow() } else { showOnboarding() }
    }

    /// 面板六態輪播（--caption-demo）
    private func runCaptionDemo() {
        let pc = DictationController.shared.panel
        var t: TimeInterval = 0.2
        func at(_ dt: TimeInterval, _ f: @escaping () -> Void) {
            t += dt
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f)
        }
        at(0) {
            pc.showListening()
            pc.update("這個 implementation 很 elegant\n要保留英文原樣")
        }
        var lv: Float = 0.2
        let lvTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            lv = max(0.05, min(1, lv + Float.random(in: -0.25...0.25)))
            pc.level(lv)
        }
        at(2.6) {
            lvTimer.invalidate()
            pc.working("整理中，用你的 Claude Code", eta: "約 2 秒")
        }
        at(2.6) { pc.pasted() }
        // 翻譯模式（左 ⌘）：聽態多一排語言籤、整理態寫翻成哪國、完成寫貼上哪國
        at(1.4) {
            pc.showListening(mode: .translate, target: .ja)
            pc.update("我們明天下午四點開會\n地點改到二樓")
            pc.level(0.55)
        }
        at(3.0) { pc.working("翻成日文中，用你的 Claude Code", eta: "約 2 秒") }
        at(2.4) { pc.pasted("已貼上日文") }
        at(2.0) { pc.copied() }
        at(2.6) { pc.error("語音引擎沒有回應。", actionTitle: "重啟引擎") {} }
        // Claude 登入過期態：字照樣貼出去，但一定要講清楚＋當場給得按的鈕
        at(2.6) {
            pc.error("Claude 登入過期了，這句先用內建模型整理", actionTitle: "重新登入") {}
        }
        at(4.0) {
            TalkyServers.shared.shutdownForQuit()  // 病史：demo 直接 exit 留下孤兒引擎佔 port
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.persistDownloadForQuit()
        TalkyServers.shared.shutdownForQuit()
        if let a = antiNap { ProcessInfo.processInfo.endActivity(a) }
    }

    /// app 已在跑時再點一次 Dock 圖示／啟動台 → 開狀態視窗
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if Dictation.onboardingDone { showStatusWindow() } else { showOnboarding() }
        return true
    }

    // ── 選單列 ──

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusSymbol()
        item.menu = buildMenu()
        statusItem = item
    }

    private func refreshStatusIcon() {
        statusItem?.button?.image = statusSymbol()
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(
            withTitle: "打開 Talky", action: #selector(menuOpen), keyEquivalent: "").target = self
        m.addItem(withTitle: "試講一句", action: #selector(menuTry), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "設定…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        m.addItem(withTitle: "設定精靈…", action: #selector(menuWizard), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "結束 Talky", action: #selector(menuQuit), keyEquivalent: "q").target =
            self
        return m
    }

    @objc private func menuOpen() { showStatusWindow() }
    @objc private func menuTry() { tryOneSentence() }
    @objc private func menuSettings() { showSettingsWindow() }
    @objc private func menuWizard() { showOnboarding() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // ── 視窗 ──

    func showOnboarding(startAt: Int? = nil) {
        if startAt != nil { onboardingWindow = nil }  // 指定步數＝重建視窗（截圖用）
        if onboardingWindow == nil {
            let view = OnboardingView(
                onFinish: { [weak self] in
                    self?.onboardingWindow?.orderOut(nil)
                    self?.showStatusWindow()
                },
                onOpenSettings: { [weak self] in self?.showSettingsWindow(tab: 1) },
                startAt: startAt)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Talky"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: view)
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func showStatusWindow() {
        if statusWindow == nil {
            let view = StatusView(
                onSettings: { [weak self] tab in self?.showSettingsWindow(tab: tab) },
                onTry: { [weak self] in self?.tryOneSentence() },
                onWizard: { [weak self] in self?.showOnboarding() })
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Talky"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: view)
            w.center()
            statusWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        statusWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettingsWindow(tab: Int = 0) {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Talky 設定"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        // 每次重掛內容：外面要的分頁（狀態視窗的大腦膠囊會直接跳「進階」）
        settingsWindow?.contentView = NSHostingView(
            rootView: SettingsView(initialTab: tab, onWizard: { [weak self] in self?.showOnboarding() }))
        settingsWindow?.setContentSize(NSSize(width: 480, height: 600))  // 跟 SettingsView 的 frame 一致，差 1pt 就切邊
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 試講一句：把游標放進狀態視窗的試講區，再開始口述（結果會直接出現在那一格）
    func tryOneSentence() {
        if onboardingWindow?.isVisible != true { showStatusWindow() }
        NotificationCenter.default.post(name: .talkyFocusTrialBox, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            DictationController.shared.toggle()
        }
    }

    // ── 通知（只有這一則）──

    /// 授權要在這裡問，不能在啟動時先問一次、就緒時再查一次：
    /// 系統的授權對話框是使用者按了才有答案，先問後查會查到「還沒決定」而白白跳過通知。
    /// requestAuthorization 對已經決定過的情況會立刻回傳既有答案，重複呼叫不會多跳窗。
    private func notifyReadyOnce() {
        guard !readyNotified, Bundle.main.bundleIdentifier != nil else { return }
        readyNotified = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, err in
            guard granted else {
                TalkyLog.write(
                    "ready notification skipped（通知未授權 \(err?.localizedDescription ?? "使用者未允許")）")
                return
            }
            let c = UNMutableNotificationContent()
            c.title = "Talky 已就緒"
            c.body = "在任何文字框\(Dictation.trigger.longLabel)就能講話。"
            c.categoryIdentifier = "ready"
            center.add(
                UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            TalkyLog.write("ready notification posted")
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "try" {
            tryOneSentence()
        } else {
            showStatusWindow()
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
            Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// ── 主選單（⌘Q／⌘C／⌘V／⌘A 這些要有人接）────────────────────

func makeMainMenu() -> NSMenu {
    let main = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
        withTitle: "關於 Talky", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "隱藏 Talky", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "結束 Talky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let edit = NSMenu(title: "編輯")
    let items: [(String, Selector, String)] = [
        ("復原", Selector(("undo:")), "z"),
        ("重做", Selector(("redo:")), "Z"),
        ("剪下", #selector(NSText.cut(_:)), "x"),
        ("拷貝", #selector(NSText.copy(_:)), "c"),
        ("貼上", #selector(NSText.paste(_:)), "v"),
        ("全選", #selector(NSText.selectAll(_:)), "a"),
    ]
    for (t, s, k) in items {
        edit.addItem(withTitle: t, action: s, keyEquivalent: k)
    }
    editItem.submenu = edit
    main.addItem(editItem)

    return main
}

// ── 進入點 ──────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// SIGTERM（kill、登出、pkill）走正常退出：applicationWillTerminate 會收引擎，不留孤兒佔 port
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { NSApp.terminate(nil) }
termSource.resume()
// .regular＝Dock 圖示與 ⌘Tab 都有（Dock 常駐）
app.setActivationPolicy(.regular)
Dictation.applyAppearance()  // 設定裡選的跟系統／淺／深
app.mainMenu = makeMainMenu()
app.run()
