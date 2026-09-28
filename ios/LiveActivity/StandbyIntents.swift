// StandbyIntents — 在原地開／關 Talky 待命（控制中心、動作按鈕、Siri、捷徑），不跳進 app
//
// 為什麼要有：iOS 不讓鍵盤開麥克風，Talky 的麥克風只能在主 app 開。平常第一次要跳一次 app；
// 用這兩個意圖就不用跳——系統在背景啟動 Talky 的行程、開好麥克風、動態島出現 Talky，你人還在原本的 App。
// AudioRecordingIntent：允許在背景開始收音（Apple 規定收音期間一定要掛著即時動態，不然收音會被停）。
// LiveActivityIntent：系統會在背景啟動 app 行程（不打開畫面）來執行，並准許在背景開即時動態。
// 這個檔同時編進主 app 與 TalkyWidgets（控制中心的按鈕要認得這個意圖）；真正做事只在主 app（TALKY_APP）。

import ActivityKit
import AppIntents
import Foundation

/// 動態島／鎖定畫面上的 Talky
struct TalkyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// ready／listening／working／done
        var phase: String
        /// 一行字：即時字幕、整理好的那句、或狀態
        var line: String
    }
}

struct StartStandbyIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talky 開始待命"
    static let description = IntentDescription("在背景開好麥克風；之後任何 App 的 Talky 鍵盤都能在原地直接講，不用跳 app。")

    func perform() async throws -> some IntentResult {
        #if TALKY_APP
        await DictationEngine.shared.armFromIntent()
        #endif
        return .result()
    }
}

struct StopStandbyIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Talky 結束待命"
    static let description = IntentDescription("關掉 Talky 的麥克風待命。")

    func perform() async throws -> some IntentResult {
        #if TALKY_APP
        await DictationEngine.shared.endSession()
        #endif
        return .result()
    }
}
