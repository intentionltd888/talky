// TalkyShortcuts — 讓「Talky 開始待命」出現在捷徑、Siri、動作按鈕的選單裡（只在主 app）

import AppIntents

struct TalkyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStandbyIntent(),
            phrases: ["用 \(.applicationName) 開始待命", "\(.applicationName) 待命", "Start \(.applicationName)"],
            shortTitle: "開始待命", systemImageName: "waveform")
        AppShortcut(
            intent: StopStandbyIntent(),
            phrases: ["\(.applicationName) 結束待命", "Stop \(.applicationName)"],
            shortTitle: "結束待命", systemImageName: "stop.circle")
    }
}
