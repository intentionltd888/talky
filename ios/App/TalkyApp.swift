// Talky iPhone 版 — 主 app
//
// 主 app 是「引擎」：收音、辨識、整理都在這裡；真正每天用的是 Talky 鍵盤（Keyboard/）。
// 平常打開＝首頁（狀態、試講、設定鍵盤、整理方式）；被鍵盤叫醒＝「回到剛剛的 App」那頁。

import SwiftUI

@main
struct TalkyApp: App {
    @StateObject private var engine = DictationEngine.shared
    @StateObject private var memo = Memo.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(memo)
                .onOpenURL { engine.handle(url: $0) }
                #if DEBUG
                .task { engine.debugFeedIfAsked() }
                #endif
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: DictationEngine
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-TalkyKeyboardProbe") {
            KeyboardProbeView(useTalky: !(i + 1 < args.count && args[i + 1] == "system"))
        } else {
            home
        }
        #else
        home
        #endif
    }

    private var home: some View {
        HomeView()
            .fullScreenCover(isPresented: $engine.showBounce) {
                BounceView()
            }
            // 回到原本的 App 之後就收掉「回去」那頁：下次打開 Talky 看到的是首頁
            .onChange(of: scenePhase) { _, p in
                if p == .background { engine.showBounce = false }
                if p == .active { engine.autoArm() }
            }
    }
}
