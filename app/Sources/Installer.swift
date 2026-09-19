// Installer.swift — 從 DMG 直接雙擊也能裝：自己搬進「應用程式」、加進 Dock、從那裡重新打開
//
// 目標：裝的時候自動加進 Dock，而且當場就能裝，不用再去「應用程式」裡找。
// DMG 是唯讀映像，拖曳過程不會執行任何程式，所以「拖完自動做事」做不到；能做的是兩條路：
//   ① 使用者直接雙擊 DMG 裡的 Talky → 這裡接手：問一次 → 複製到 /Applications → 加進 Dock → 從新位置打開 → 退出舊的、退出磁碟映像
//   ② 使用者照舊拖進「應用程式」再打開 → 第一次從 /Applications 啟動時把自己加進 Dock（只做一次，見 main.swift）
// 權限（麥克風、輔助使用）綁的是「路徑＋簽名」，所以一定要先落在 /Applications 才開始要權限——這也是舊版直接擋下 /Volumes 的原因。
import Cocoa

enum Installer {
    static let appName = "Talky"
    static var installedURL: URL { URL(fileURLWithPath: "/Applications/\(appName).app") }

    /// 從磁碟映像跑（含 macOS 對「下載回來的 app」套的 App Translocation 隨機路徑）
    static var isRunningFromDiskImage: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Volumes/") || p.contains("/AppTranslocation/")
    }
    static var isRunningFromApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    /// DMG 裡雙擊的入口。問一次；同意就自己裝好並從 /Applications 重開（本行程隨後 exit），拒絕就教他拖然後 exit。
    /// autoYes＝命令列 `--install`（測試鉤），不跳問句直接裝。
    @MainActor static func offerInstallFromDiskImage(autoYes: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        var yes = autoYes
        if !yes {
            let a = NSAlert()
            a.messageText = "把 Talky 放進「應用程式」？"
            a.informativeText = "Talky 會自己複製到「應用程式」、加進 Dock，然後從那裡打開。之後直接點 Dock 上的圖示就好。"
            a.addButton(withTitle: "放進應用程式並打開")
            a.addButton(withTitle: "我自己拖")
            yes = a.runModal() == .alertFirstButtonReturn
        }
        guard yes else {
            let a = NSAlert()
            a.messageText = "先安裝再打開"
            a.informativeText = "請把 Talky 拖進「應用程式」資料夾，再從那裡打開。"
            a.runModal()
            exit(0)
        }
        do {
            try install()
        } catch {
            TalkyLog.write("install failed: \(error)")
            let a = NSAlert()
            a.messageText = "沒辦法自動放進「應用程式」"
            a.informativeText = "\(error.localizedDescription)\n\n請把 Talky 拖進「應用程式」資料夾，再從那裡打開。"
            a.runModal()
            exit(1)
        }
        // 從新位置重開；把磁碟映像路徑傳過去，讓新的那顆在我們退出後把它退出
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        // 病史：同 bundle id 已在跑時，openApplication 只會「切到」正在跑的這顆（就是 DMG 裡的自己），
        // 新的那顆根本沒起來，六秒後自己退出＝使用者面前什麼都沒有。要明講開新實例。
        cfg.createsNewApplicationInstance = true
        if let v = diskImageVolume() { cfg.arguments = ["--eject", v] }
        NSWorkspace.shared.openApplication(at: installedURL, configuration: cfg) { _, err in
            if let err { TalkyLog.write("relaunch failed: \(err)") }
            DispatchQueue.main.async { exit(0) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { exit(0) }  // 保險：completion 沒回也退
    }

    /// 複製到 /Applications（舊版先請它退出、丟垃圾桶可還原，不 rm），再釘進 Dock
    static func install() throws {
        let fm = FileManager.default
        let src = Bundle.main.bundleURL
        let dst = installedURL
        let me = ProcessInfo.processInfo.processIdentifier
        let bid = Bundle.main.bundleIdentifier ?? "ltd.intention.talky"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid).filter { $0.processIdentifier != me }
        for r in others { r.terminate() }
        let deadline = Date().addingTimeInterval(6)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        for r in others where !r.isTerminated { r.forceTerminate() }
        if fm.fileExists(atPath: dst.path) {
            var trashed: NSURL?
            try fm.trashItem(at: dst, resultingItemURL: &trashed)
        }
        try fm.copyItem(at: src, to: dst)
        TalkyLog.write("installed to \(dst.path) from \(src.path)")
        Dock.ensure(appURL: dst)
    }

    /// 正在跑的這顆若在 /Volumes/<名稱>/ 底下就回那個掛載點；被 App Translocation 搬走的話找 /Volumes/Talky
    static func diskImageVolume() -> String? {
        let p = Bundle.main.bundlePath
        if p.hasPrefix("/Volumes/") {
            let parts = p.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 2 { return "/Volumes/\(parts[1])" }
        }
        let guess = "/Volumes/\(appName)"
        if FileManager.default.fileExists(atPath: "\(guess)/\(appName).app") { return guess }
        return nil
    }

    /// `--eject /Volumes/Talky`：從 /Applications 重開後把磁碟映像退出（舊行程要先走完，所以延後；忙碌就再試一次 -force）
    static func ejectLater(_ volume: String) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            func detach(_ force: Bool) -> Bool {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                p.arguments = ["detach", volume] + (force ? ["-force"] : [])
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { return false }
                p.waitUntilExit()
                return p.terminationStatus == 0
            }
            if !detach(false) {
                Thread.sleep(forTimeInterval: 3)
                _ = detach(true)
            }
            TalkyLog.write("ejected \(volume)")
        }
    }
}

enum Dock {
    /// 把 app 釘進 Dock（已經在就不動）。改的是 com.apple.dock 的 persistent-apps，重啟 Dock 才會顯示（閃一下，只此一次）。
    @discardableResult static func ensure(appURL: URL) -> Bool {
        let domain = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        var apps = (CFPreferencesCopyAppValue(key, domain) as? [[String: Any]]) ?? []
        let want = appURL.standardizedFileURL.path
        let already = apps.contains { tile in
            guard let td = tile["tile-data"] as? [String: Any],
                  let fd = td["file-data"] as? [String: Any],
                  let s = fd["_CFURLString"] as? String,
                  let u = URL(string: s) else { return false }
            return u.standardizedFileURL.path == want
        }
        if already { return false }
        apps.append([
            "tile-data": ["file-data": ["_CFURLString": "file://\(want)/", "_CFURLStringType": 15]],
            "tile-type": "file-tile",
        ])
        CFPreferencesSetAppValue(key, apps as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        try? p.run()
        TalkyLog.write("dock: pinned \(want)")
        return true
    }
}
