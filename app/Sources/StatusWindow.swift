// StatusWindow — 狀態視窗（點 Dock 圖示開的那個）
//
// 重排：一行狀態＋大腦膠囊、一顆主鈕「試講一句」、試講區、
// 一條「待處理」凹槽（同時最多一項、沒事不佔位）、備忘錄升成主內容、頁尾 Powered by。
// 錯誤不發通知，只在這裡與浮動面板上講。

import AppKit
import SwiftUI

struct StatusView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var memo = Memo.shared
    var onSettings: (Int) -> Void
    var onTry: () -> Void
    var onWizard: () -> Void = {}

    @State private var trial = ""
    @FocusState private var trialFocused: Bool
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: NeuSpace.lg) {
            header
            NeuCapsuleButton(title: state.headline == "聽寫中" ? "結束並貼上" : "試講一句") { onTry() }
            trialBox
            pendingStrip
            memoSection
            PoweredBy()
        }
        .padding(NeuSpace.xl)
        .frame(width: 460, height: 620, alignment: .top)
        .background(Neu.stage)
        .onReceive(NotificationCenter.default.publisher(for: .talkyFocusTrialBox)) { _ in
            trialFocused = true
        }
    }

    private var markMode: TalkyMark.Mode {
        switch state.health {
        case .dictating: return .listening
        case .starting: return .working
        default: return .idle
        }
    }

    private var header: some View {
        HStack(spacing: NeuSpace.md) {
            TalkyMark(mode: markMode, size: 12).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.headline).font(NeuFont.ui(NeuType.title, true)).foregroundColor(Neu.inkStrong)
                    .lineLimit(1)
                Text(state.subline).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NeuSpace.sm)
            NeuChip(title: PolishMode.current.shortLabel + (ClaudeCLI.coolingDown && PolishMode.current == .claudeCLI ? "（暫退本機）" : "")) { onSettings(1) }
            NeuIconButton(systemName: "gearshape", size: 30) { onSettings(0) }
        }
    }

    /// 試講區：按下「試講一句」時游標會落在這裡，講完的字直接出現在這格。
    private var trialBox: some View {
        VStack(alignment: .leading, spacing: NeuSpace.xs) {
            Text("試講區").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
            TextEditor(text: $trial)
                .font(NeuFont.ui(NeuType.caption))
                .focused($trialFocused)
                .frame(height: 52)
                .scrollContentBackground(.hidden)
                .padding(NeuSpace.sm)
                .neuDebossed(NeuRadius.card, depth: 0.9)
                .overlay(alignment: .topLeading) {
                    if trial.isEmpty {
                        Text("講完的字會出現在這裡").font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkSoft)
                            .padding(NeuSpace.md).allowsHitTesting(false)
                    }
                }
        }
    }

    /// 待處理：同時只顯示最重要的一項；沒事就不出現（不佔位、不跳動）
    @ViewBuilder private var pendingStrip: some View {
        if let f = state.downloadFraction {
            HStack(spacing: NeuSpace.md) {
                NeuGroove(fill: CGFloat(f), height: 10).frame(maxWidth: 160)
                Text(String(format: "下載中 %.0f%%", f * 100)).font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkMid)
                Spacer()
                NeuChip(title: "取消") { state.cancelDownload() }
            }
            .padding(.horizontal, NeuSpace.lg).padding(.vertical, NeuSpace.sm)
            .neuDebossed(NeuRadius.pill, depth: 0.85)
        } else if case .broken = state.health {
            strip("引擎有問題", "重啟引擎") { state.restartEngines() }
        } else if !state.whisperModelReady {
            strip("還缺語音模型（1.5GB，只下載這一次）", "下載") { state.downloadWhisperModel() }
        } else if !state.axTrusted {
            strip("沒開輔助使用：連按右 ⌘ 不會有反應（開完自動接上，不用重開）", "去開啟") {
                Dictation.requestAXTrust()
                Dictation.openAXSettings()
            }
        } else if !state.hotkeyActive {
            strip("快捷鍵沒接上：這台 macOS 還要「輸入監控」權限", "去開啟") {
                Dictation.openInputMonitoringSettings()
            }
        } else if state.siblingIMEConflict {
            strip("同一家的會議記錄 app 也在聽右 ⌘，兩邊會搶", "關掉它的輸入法") {
                SharedPaths.disableSiblingIME()
                state.refresh()
            }
        } else if !state.downloadNote.isEmpty {
            NeuNote(text: state.downloadNote)
        }
    }

    private func strip(_ text: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        HStack(spacing: NeuSpace.sm) {
            Text(text).font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer()
            NeuChip(title: action, action: run)
        }
        .padding(.horizontal, NeuSpace.lg).padding(.vertical, NeuSpace.sm)
        .neuDebossed(NeuRadius.pill, depth: 0.85)
    }

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: NeuSpace.sm) {
            HStack {
                Text("備忘錄").font(NeuFont.ui(NeuType.body, true)).foregroundColor(Neu.inkStrong)
                Text("最近 \(Memo.limit) 句，點一下複製").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
                Spacer()
                if !memo.entries.isEmpty {
                    if confirmClear {
                        NeuChip(title: "確定清空（已先複製到剪貼簿）") {
                            let all = memo.entries.map { "\($0.timeLabel) \($0.text)" }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(all, forType: .string)
                            memo.clear()
                            confirmClear = false
                        }
                    } else {
                        NeuChip(title: "清空") { confirmClear = true }
                    }
                }
            }
            if memo.entries.isEmpty {
                Text("講過的句子會留在這裡。")
                    .font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, NeuSpace.sm)
            } else {
                ScrollView {
                    VStack(spacing: NeuSpace.sm) {
                        ForEach(memo.entries) { e in MemoRow(entry: e) }
                    }
                    .padding(.vertical, NeuSpace.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

extension Notification.Name {
    /// 「試講一句」按下時，把游標放進試講區
    static let talkyFocusTrialBox = Notification.Name("talkyFocusTrialBox")
}

private struct MemoRow: View {
    let entry: MemoEntry
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: NeuSpace.md) {
            Text(entry.timeLabel)
                .font(NeuFont.mark(NeuType.micro, false))
                .foregroundColor(Neu.inkSoft)
                .frame(width: 38, alignment: .leading)
            Text(entry.text)
                .font(NeuFont.ui(NeuType.caption))
                .foregroundColor(Neu.inkStrong)
                .lineLimit(hovering ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(copied ? "已複製" : (hovering && !entry.pasted ? "未貼上" : ""))
                .font(NeuFont.ui(NeuType.micro))
                .foregroundColor(copied ? Neu.inkStrong : Neu.inkSoft)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, NeuSpace.md)
        .padding(.vertical, NeuSpace.sm)
        .neuDebossed(NeuRadius.card, depth: hovering ? 0.95 : 0.7)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
        }
    }
}
