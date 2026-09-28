// TalkyWidgets — 控制中心的「Talky 待命」按鈕＋動態島／鎖定畫面的 Talky
//
// 控制中心、動作按鈕（設定 → 動作按鈕 → 控制項 → Talky 待命）按一下：在原地開待命，不跳 app。
// 待命期間動態島顯示米字與狀態（待命／聽／整理），展開看得到字幕與「結束」鈕。

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TalkyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TalkyStandbyControl()
        TalkyLiveActivity()
    }
}

// MARK: - 控制中心／動作按鈕

struct TalkyStandbyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ltd.intention.talky.ios.standby") {
            ControlWidgetButton(action: StartStandbyIntent()) {
                Label("Talky 待命", systemImage: "waveform")
            }
        }
        .displayName("Talky 待命")
        .description("在原地開好麥克風，鍵盤直接講、不用跳 app")
    }
}

// MARK: - 即時動態（動態島＋鎖定畫面）

struct TalkyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TalkyActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TalkyMarkShape().fill(.white).frame(width: 18, height: 18).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopStandbyIntent()) {
                        Text("結束").font(.system(size: 13, weight: .semibold))
                    }
                    .tint(.white.opacity(0.25))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.line)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                TalkyMarkShape().fill(.white).frame(width: 14, height: 14)
            } compactTrailing: {
                Text(phaseLabel(context.state.phase))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(context.state.phase == "listening" ? .white : .white.opacity(0.7))
            } minimal: {
                TalkyMarkShape().fill(.white).frame(width: 12, height: 12)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: TalkyActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            TalkyMarkShape().fill(.white).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Talky・\(phaseLabel(state.phase))").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(state.line).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Button(intent: StopStandbyIntent()) {
                Text("結束").font(.system(size: 13, weight: .semibold))
            }
            .tint(.white.opacity(0.25))
        }
        .padding(16)
    }
}

private func phaseLabel(_ p: String) -> String {
    switch p {
    case "listening": return "聽"
    case "working": return "整理"
    case "done": return "好了"
    default: return "待命"
    }
}
