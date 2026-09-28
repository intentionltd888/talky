// KeyboardView — Talky 鍵盤的長相（L1「儀器面板」排版）
//
// ┌──────────────────────────────────────────┐
// │ ╭──────────────────────────────────────╮ │
// │ │ ✳︎ (翻成泰文・女生朋友)   [取消]／*talky │ │  顯示窗（凹）：米字＋翻譯標籤＋右邊小膠囊
// │ │ 你今天下班之後有空嗎？我想請你吃飯｜     │ │  字幕／意思／提示
// │ │ ╰───(▬)──────────────────────────╯   │ │  凹槽音量條（聽的時候）
// │ ╰──────────────────────────────────────╯ │
// │        (空白)     (  ●  )     (⌫)         │  三顆圓鈕：空白／錨圓鈕／刪除（位置永遠不動）
// │ (🌐) (══════════ 換行 ══════════)        │  長膠囊
// └──────────────────────────────────────────┘
// 世界觀跟 Mac 版一樣：一塊材料，凸起＝可按、凹陷＝容器或已選；材料色＝原生鍵盤的灰（見 Shared/Theme.swift）。
// 點一下圓鈕＝講中文；長按圓鈕往上滑＝顯示窗裡排開翻譯目標，停在哪個（凹下去）放開就開始講、這句翻成它。
// 復原／中文（原文）／貼上／取消都放在顯示窗右上：底下三顆鈕不會因為狀態換位置，手指記得住。

import SwiftUI

struct KeyboardView: View {
    static let height: CGFloat = 290
    static let windowHeight: CGFloat = 100
    /// 長按時翻譯目標在顯示窗那一區排開：手指要滑進這條上面才算選到
    static let chooserBand: CGFloat = 118
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                displayWindow
                    .frame(height: Self.windowHeight)
                Spacer(minLength: 8)
                buttonRow
                Spacer(minLength: 8)
                bottomRow
                    .frame(height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay(alignment: .top) {
                if model.choosing { chooser(width: geo.size.width).transition(.opacity) }
            }
            .animation(NeuMotion.ui, value: model.choosing)
        }
        .coordinateSpace(name: "kb")
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Neu.material)
    }

    // MARK: 顯示窗（凹）：米字＋標籤＋右上小膠囊／字幕／凹槽

    private var displayWindow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TalkyMark(mode: markMode, size: 13)
                    .frame(width: 26, height: 26)
                if let t = model.turnOut, model.phase == .listening || model.phase == .working {
                    Text("翻成\(t.label)")
                        .font(NeuFont.ui(12))
                        .foregroundStyle(Neu.inkMid)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .neuRaised(NeuRadius.pill, lift: 0.35)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                accessory
            }
            .frame(height: 30)
            Text(statusText)
                .font(NeuFont.ui(model.phase == .listening && !model.partial.isEmpty ? 16 : 14.5))
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .truncationMode(model.phase == .listening || model.phase == .working ? .head : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: statusText)
            if model.phase == .listening {
                NeuGroove(fill: CGFloat(min(1, model.level * 1.4)), height: 10)
            } else if model.phase == .working {
                NeuGroove(fill: nil, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .neuDebossed(NeuRadius.card, depth: 0.9)
        .opacity(model.choosing ? 0 : 1)
    }

    /// 顯示窗右上：聽＝取消；剛打上＝復原＋中文（原文）；有一句沒貼＝貼上；其他＝*talky
    @ViewBuilder private var accessory: some View {
        if model.phase == .listening {
            NeuChip(title: "取消", height: 26) { model.cancelListening() }
        } else if model.phase == .working {
            EmptyView()
        } else if model.lastInsert != nil {
            HStack(spacing: 8) {
                NeuChip(title: "↶ 復原", height: 26) { model.undo() }
                if let li = model.lastInsert, let raw = li.raw, raw != li.text {
                    NeuChip(title: model.lastLang == nil ? "原文" : "中文", height: 26) { model.useRaw() }
                }
            }
        } else if model.pending != nil {
            NeuChip(title: "貼上", height: 26) { model.insertPending() }
        } else {
            TalkyLogotype(height: 14, color: Neu.inkSoft)
        }
    }

    private var markMode: TalkyMark.Mode {
        switch model.phase {
        case .listening: return .listening
        case .working: return .working
        default: return model.lastInsert != nil ? .flash : .idle
        }
    }

    private var statusText: String {
        if !model.fullAccess { return "要先開「允許完整取用」才能收音：設定 → 一般 → 鍵盤 → 鍵盤 → Talky" }
        switch model.phase {
        case .listening:
            return model.partial.isEmpty ? "正在聽…講完再點一下" : model.partial
        case .working:
            let doing = model.turnOut == nil ? "整理中…" : "翻譯中…"
            return model.partial.isEmpty ? doing : doing + "　" + model.partial
        default:
            if let n = model.notice, !n.isEmpty, model.lastInsert == nil { return n }
            if model.lastInsert != nil {
                if let b = model.lastBack, !b.isEmpty { return "意思：" + b }
                return "已打上"
            }
            if let p = model.pending { return "還沒貼：\(p.text)" }
            if !model.appAlive { return "Talky 沒在待命：點一下圓鈕會先跳去開麥克風" }
            return model.targets.isEmpty ? "點一下開始講，講完再點一下" : "點一下講中文・長按往上滑＝翻譯"
        }
    }

    private var statusColor: Color {
        if !model.fullAccess { return Neu.warn }
        if model.phase == .listening && !model.partial.isEmpty { return Neu.inkStrong }
        if model.phase != .listening, model.phase != .working, let n = model.notice, !n.isEmpty,
            model.lastInsert == nil
        {
            return Neu.warn
        }
        return Neu.inkMid
    }

    // MARK: 三顆圓鈕：空白／錨圓鈕／刪除

    private var buttonRow: some View {
        HStack(spacing: 26) {
            Button { model.type(" ") } label: {
                Text("空白").font(NeuFont.ui(15)).foregroundStyle(Neu.inkStrong)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(NeuPressStyle(radius: NeuRadius.pill, lift: 0.7))
            MicControl(model: model)
            DeleteKey(model: model, radius: NeuRadius.pill)
                .frame(width: 60, height: 60)
        }
        .frame(maxWidth: .infinity)
        .opacity(model.choosing ? 0.9 : 1)
    }

    // MARK: 最下排：🌐（系統沒給的時候）＋長膠囊換行

    private var bottomRow: some View {
        HStack(spacing: 10) {
            if model.needsGlobe {
                Button { model.nextKeyboard() } label: {
                    Image(systemName: "globe").font(.system(size: 17))
                        .foregroundStyle(Neu.inkStrong)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(NeuPressStyle(radius: NeuRadius.pill, lift: 0.6))
                .accessibilityLabel("下一個鍵盤")
            }
            Button { model.type("\n") } label: {
                Text(model.returnKeyLabel).font(NeuFont.ui(16)).foregroundStyle(Neu.inkStrong)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(NeuPressStyle(radius: NeuRadius.pill, lift: 0.6))
        }
        .opacity(model.choosing ? 0.35 : 1)
    }

    // MARK: 長按：顯示窗那一區排開翻譯目標（停在哪個就凹下去＝已選）

    private func chooser(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            if model.targets.isEmpty {
                Text("還沒有翻譯目標：打開 Talky → 翻譯目標，加一個")
                    .font(NeuFont.ui(14)).foregroundStyle(Neu.inkMid)
                    .frame(maxWidth: .infinity).frame(height: 72)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(model.targets.enumerated()), id: \.element.id) { i, t in
                        let on = model.hover == i
                        VStack(spacing: 2) {
                            Text(t.lang.label).font(NeuFont.ui(16, true))
                            Text(t.situation.label).font(NeuFont.ui(12)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(on ? Neu.inkStrong : Neu.inkMid)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background {
                            if on {
                                Color.clear.neuDebossed(NeuRadius.card, depth: 1)
                            } else {
                                Color.clear.neuRaised(NeuRadius.card, lift: 0.7)
                            }
                        }
                        .animation(NeuMotion.press, value: on)
                    }
                }
                Text(model.hover == nil ? "往上滑到語言，放開開始講（放在別處＝取消）" : "放開開始講，講完再點一下")
                    .font(NeuFont.ui(12)).foregroundStyle(Neu.inkMid)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .allowsHitTesting(false)
    }
}

/// 錨圓鈕＋手勢：點一下＝開始／講完；長按（或直接往上滑）＝挑翻譯目標，放開＝開始講
struct MicControl: View {
    @ObservedObject var model: KeyboardModel
    @State private var down = false
    @State private var hold: Task<Void, Never>?

    var body: some View {
        GeometryReader { g in
            let width = g.frame(in: .named("kb")).maxX + g.frame(in: .named("kb")).minX
            NeuAnchorFace(
                glyph: model.phase == .listening ? .square : .dot, size: 80, level: CGFloat(model.level),
                pressed: down && !model.choosing, dimmed: model.phase == .working
            )
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("kb"))
                    .onChanged { v in
                        if !down {
                            down = true
                            if model.canChoose {
                                hold?.cancel()
                                hold = Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    guard !Task.isCancelled, down else { return }
                                    model.beginChoosing()
                                }
                            }
                        }
                        // 不用等：直接往上滑也算長按
                        if !model.choosing, model.canChoose, v.startLocation.y - v.location.y > 26 {
                            model.beginChoosing()
                        }
                        if model.choosing {
                            model.hoverAt(v.location, width: width, bandBottom: KeyboardView.chooserBand)
                        }
                    }
                    .onEnded { _ in
                        hold?.cancel()
                        hold = nil
                        down = false
                        if model.choosing {
                            model.endChoosing()
                        } else {
                            model.micTapped()
                        }
                    }
            )
        }
        .frame(width: 112, height: 112)
        .accessibilityElement()
        .accessibilityLabel(model.phase == .listening ? "講完了" : "開始講中文")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.micTapped() }
        .accessibilityActions {
            ForEach(model.targets) { t in
                Button("翻成\(t.label)") { model.startTranslate(t) }
            }
        }
    }
}

/// 刪除鍵：按住會連刪
struct DeleteKey: View {
    @ObservedObject var model: KeyboardModel
    var radius: CGFloat = NeuRadius.key
    @State private var down = false

    var body: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 19))
            .foregroundStyle(Neu.inkStrong)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .neuRaised(radius, lift: 0.7, pressed: down)
            .animation(NeuMotion.press, value: down)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            model.startDeleteRepeat()
                        }
                    }
                    .onEnded { _ in
                        down = false
                        model.stopDeleteRepeat()
                    }
            )
            .accessibilityLabel("刪除")
            .accessibilityAddTraits(.isButton)
    }
}
