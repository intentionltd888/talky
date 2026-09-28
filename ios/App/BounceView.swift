// BounceView — 被鍵盤叫醒時的那一頁
//
// iOS 鍵盤不能開麥克風，所以第一次按麥克風會跳來這裡把麥克風打開（之後待命期間不用再跳）。
// 這頁只做一件事：告訴使用者「已經在聽了，點左上角回去繼續講」。

import SwiftUI

struct BounceView: View {
    @EnvironmentObject private var engine: DictationEngine

    private var s: LiveState { engine.state }

    var body: some View {
        ZStack {
            Neu.material.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // 指向系統放在左上角的「◀ 返回」
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Neu.inkStrong)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("點左上角「◀」回到剛剛的 App")
                            .font(.headline)
                            .foregroundStyle(Neu.inkStrong)
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(Neu.inkMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 16) {
                    TalkyMark(mode: markMode, size: 26)
                    Text(bodyText)
                        .font(.system(size: 20, weight: s.phase == .done ? .semibold : .regular))
                        .foregroundStyle(s.partial.isEmpty && s.phase == .listening ? Neu.inkMid : Neu.inkStrong)
                        .multilineTextAlignment(.center)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity)
                        .animation(NeuMotion.ui, value: bodyText)
                    if let p = engine.assetProgress {
                        Text("第一次使用：下載中文語音模型 \(Int(p * 100))%")
                            .font(.footnote)
                            .foregroundStyle(Neu.inkMid)
                    }
                    if let m = s.message, !m.isEmpty {
                        Text(m).font(.footnote).foregroundStyle(Neu.warn)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                VStack(spacing: 16) {
                    if s.phase == .listening || s.phase == .ready || s.phase == .off {
                        NeuAnchorButton(glyph: s.phase == .listening ? .square : .dot, size: 84, level: CGFloat(s.level)) {
                            if s.phase == .listening {
                                engine.stopListening()
                            } else {
                                engine.startListening(target: .keyboard)
                            }
                        }
                    }
                    Button("關閉這頁") { engine.showBounce = false }
                        .font(.footnote)
                        .foregroundStyle(Neu.inkMid)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }

    private var markMode: TalkyMark.Mode {
        switch s.phase {
        case .listening: return .listening
        case .working: return .working
        case .done: return .flash
        default: return .idle
        }
    }

    private var hint: String {
        switch s.phase {
        case .done: return "整理好了，回去就會自動打進你剛剛的輸入框。"
        case .working: return "整理中，回去就會自動打進輸入框。"
        default: return "麥克風已經開了，回去直接講；講完在鍵盤上再點一下圓鈕。"
        }
    }

    private var bodyText: String {
        switch s.phase {
        case .listening: return s.partial.isEmpty ? "正在聽…" : s.partial
        case .working: return s.partial.isEmpty ? "整理中…" : s.partial
        case .done: return s.result ?? ""
        case .ready: return "待命中，按下面的鈕或回鍵盤講"
        case .off, .failed: return "麥克風還沒開"
        }
    }
}
