// Neu — 軟浮雕（neumorphism）設計系統 ＋ Talky 身份元件
//
// 世界觀：整個介面是**一塊材料**，面板與背景同色，形狀只由「雙向陰影」造出來
// （光源固定左上：亮高光在左上、暗影在右下）。凸起＝可按；凹陷＝容器或已選。
//
// 介面重置（深色版的長相，黑白跟系統走）：
// ・色票全部改成「跟系統外觀走」的動態色：淺色＝原本的白材料，深色＝#2B2D33 材料。
//   所有既有呼叫點（Neu.material／Neu.inkStrong…）不用改，NSColor 動態供應器會依外觀切換。
// ・Talky 身份三件：TalkyMark（六臂圓頭米字，取代白珍珠光點）、TalkyLogotype（*talky 標準字圖）、
//   IntentionWordmark（INTENTION® 字標圖；用到 INTENTION 字標一律用這張 png）。
// ・字型走系統字（開源版不散布任何字型檔）；標準字與字標是圖檔（見 Resources/Brand/TRADEMARK.md）。

import AppKit
import SwiftUI

// MARK: - 動態色（淺／深各一組，跟系統外觀切換）

private func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        })
}

enum Neu {
    /// 材料本色：面板與背景同一個色，靠陰影分層（死刑清單：面板不得與底不同色）
    static let material = dyn(0xEEEFF2, 0x2B2D33)
    /// 舞台底（比材料再暗一點點，讓面板浮起來）
    static let stage = dyn(0xE7E8EC, 0x1E1F23)

    /// 左上高光（深色模式下是一道很淡的亮邊，不是白光暈）
    static let light = dyn(0xFFFFFF, 0x3E4149)
    /// 右下影
    static let shade = dyn(0xA3A6AF, 0x0E0F12)

    /// 墨三階（軟浮雕天生低對比，正文一律用 primary，禁止淺灰壓淺灰）
    static let inkStrong = dyn(0x282A2F, 0xE8E9EC)
    static let inkMid = dyn(0x73767E, 0xA6A8B0)
    static let inkSoft = dyn(0xA2A5AD, 0x8E9099)

    /// 主行動鈕的面：比材料再深一階（不用黑，質感更好）
    static let keyFace = dyn(0xE0E2E6, 0x35383F)
    static let keyFaceDeep = dyn(0xD3D6DB, 0x2A2C32)

    /// 亮藍光（只留給極少數「正在進行」的光點；介面主體不用藍）
    static let glowCore = Color.white
    static let glowMid = Color(red: 0.310, green: 0.788, blue: 1.0)  // #4FC9FF
    static let glowEdge = Color(red: 0.039, green: 0.639, blue: 0.965)  // #0AA3F6
}

/// 4pt 網格
enum NeuSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let hero: CGFloat = 32
    /// 面板內縮
    static let edge: CGFloat = 24
}

/// 字級
enum NeuType {
    static let hero: CGFloat = 28  // 精靈頁大標
    static let timer: CGFloat = 40
    static let title: CGFloat = 18
    static let body: CGFloat = 14
    static let caption: CGFloat = 12.5
    static let micro: CGFloat = 11
}

enum NeuRadius {
    static let panel: CGFloat = 22
    static let card: CGFloat = 18
    static let pill: CGFloat = 999
}

enum NeuMotion {
    static let press = Animation.easeOut(duration: 0.14)
    static let ui = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let pulse = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
}

// MARK: - 材質修飾器

/// 凸起：從材料裡壓出來，可按。光源左上。
struct NeuRaised: ViewModifier {
    var radius: CGFloat = NeuRadius.card
    var lift: CGFloat = 1
    var pressed: Bool = false

    func body(content: Content) -> some View {
        let blur = 7 * lift
        let offset = 4 * lift
        // 亮高光只留一半的暈（病史：小膠囊的亮暈跑到凹框的邊線外，看起來沒對齊；
        // 深影在右下較不顯眼，維持）
        let lightBlur = blur * 0.5
        let lightOffset = offset * 0.6
        return
            content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Neu.material)
                    .shadow(
                        color: Neu.light.opacity(pressed ? 0.35 : 0.9),
                        radius: lightBlur, x: -lightOffset, y: -lightOffset
                    )
                    .shadow(
                        color: Neu.shade.opacity(pressed ? 0.18 : 0.45),
                        radius: blur * 1.15, x: offset, y: offset
                    )
            )
            .scaleEffect(pressed ? 0.985 : 1)
            // 凸起件整體右移 2pt：亮暈往左外溢的量，讓「看起來的左邊」跟凹框的左邊對齊
            .padding(.leading, 2)
    }
}

/// 凹陷：壓進材料裡。容器、已選、槽。
struct NeuDebossed: ViewModifier {
    var radius: CGFloat = NeuRadius.card
    var depth: CGFloat = 1

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    Neu.material
                        .shadow(
                            .inner(
                                color: Neu.shade.opacity(0.42 * depth), radius: 4 * depth,
                                x: 2.5 * depth, y: 2.5 * depth)
                        )
                        .shadow(
                            .inner(
                                color: Neu.light.opacity(0.95 * depth), radius: 4 * depth,
                                x: -2.5 * depth, y: -2.5 * depth))
                )
        )
    }
}

extension View {
    func neuRaised(_ radius: CGFloat = NeuRadius.card, lift: CGFloat = 1, pressed: Bool = false)
        -> some View
    {
        modifier(NeuRaised(radius: radius, lift: lift, pressed: pressed))
    }
    func neuDebossed(_ radius: CGFloat = NeuRadius.card, depth: CGFloat = 1) -> some View {
        modifier(NeuDebossed(radius: radius, depth: depth))
    }
}

enum NeuFont {
    /// 中文與一般介面字（系統字：跟著使用者的語言設定走，不綁任何字型檔）
    static func ui(_ size: CGFloat, _ semi: Bool = false) -> Font {
        .system(size: size, weight: semi ? .semibold : .regular)
    }
    /// 字標與數字
    static func mark(_ size: CGFloat, _ semi: Bool = true) -> Font {
        .system(size: size, weight: semi ? .semibold : .regular, design: .rounded)
    }
}

// MARK: - Talky 身份：六臂圓頭米字

/// Talky 的 Logo 形狀：三根圓頭長條各轉 60°＝六臂。app 圖示（make-icon.swift）用同一套幾何。
struct TalkyMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * 0.42
        var p = Path()
        for k in 0..<3 {
            let bar = Path(
                roundedRect: CGRect(x: -w / 2, y: -r, width: w, height: 2 * r), cornerRadius: w / 2)
            let t = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: CGFloat(k) * .pi / 3)
            p.addPath(bar.applying(t))
        }
        return p
    }
}

/// 米字光點：每畫面恰一顆，只標「正在進行／剛完成」（取代 Hearby 的白珍珠）。
/// 四態：idle 靜止／listening 呼吸光暈／working 等速旋轉（60°／1.8 秒，六臂對稱＝無縫；
/// 系統開「減少動態」時不轉只呼吸）／flash 一閃（完成）。
struct TalkyMark: View {
    enum Mode: Equatable { case idle, listening, working, flash }
    var mode: Mode = .idle
    var size: CGFloat = 16
    var color: Color = Neu.inkStrong

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var spin: Double = 0
    @State private var flashOn = false

    var body: some View {
        ZStack {
            if mode == .listening || mode == .working {
                TalkyMarkShape().fill(color)
                    .frame(width: size, height: size)
                    .blur(radius: size * 0.45)
                    .opacity(breathe ? 0.8 : 0.3)
            }
            if mode == .flash {
                Circle()
                    .stroke(color.opacity(flashOn ? 0 : 0.9), lineWidth: 1.2)
                    .frame(width: size * (flashOn ? 2.3 : 1.2), height: size * (flashOn ? 2.3 : 1.2))
            }
            TalkyMarkShape().fill(color)
                .frame(width: size, height: size)
                .scaleEffect(mode == .listening && breathe ? 1.05 : 1)
                .rotationEffect(.degrees(spin))
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear { apply(mode) }
        .onChange(of: mode) { _, m in apply(m) }
        // 藏起來就當成 idle：呼吸與旋轉都是 `.repeatForever`，不明講會一直重排（見 NeuGroove.setDrift）
        .onDisappear { apply(.idle) }
    }

    private func apply(_ m: Mode) {
        switch m {
        case .listening, .working:
            withAnimation(NeuMotion.pulse) { breathe = true }
        default:
            withAnimation(.easeOut(duration: 0.3)) { breathe = false }
        }
        if m == .working, !reduceMotion {
            spin = 0
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { spin = 60 }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { spin = 0 }
        }
        if m == .flash {
            flashOn = false
            withAnimation(.easeOut(duration: 0.55)) { flashOn = true }
        } else {
            flashOn = false
        }
    }
}

// MARK: - 品牌圖檔（Resources/Brand；商標，不在 MIT 範圍，見 TRADEMARK.md）

enum Brand {
    private static func image(_ name: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Brand/\(name)") else {
            return nil
        }
        let img = NSImage(contentsOf: url)
        img?.isTemplate = true
        return img
    }
    static let logotype = image("talky_logotype.png")
    static let intention = image("intention_wordmark.png")
}

/// *talky 標準字（草率手寫那顆）；圖檔缺失時退成文字，不讓版面破。
struct TalkyLogotype: View {
    var height: CGFloat = 14
    var color: Color = Neu.inkSoft
    var body: some View {
        if let img = Brand.logotype {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(height: height).foregroundColor(color)
                .accessibilityLabel("Talky")
        } else {
            Text("*talky").font(NeuFont.mark(height, true)).italic().foregroundColor(color)
        }
    }
}

/// *talky 標準字滿版（歡迎頁 B2 海報版用：字標吃滿內容寬）
struct TalkyLogotypeWide: View {
    var color: Color = Neu.inkStrong
    var body: some View {
        if let img = Brand.logotype {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(maxWidth: .infinity).foregroundColor(color)
                .accessibilityLabel("Talky")
        } else {
            Text("*talky").font(NeuFont.mark(48, true)).italic().foregroundColor(color)
        }
    }
}

/// INTENTION® 字標（永遠用圖，不打字）
struct IntentionWordmark: View {
    var height: CGFloat = 9
    var color: Color = Neu.inkSoft
    var body: some View {
        if let img = Brand.intention {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(height: height).foregroundColor(color)
                .accessibilityLabel("INTENTION")
        } else {
            Text("INTENTION®").font(NeuFont.mark(height + 1)).tracking(1.5).foregroundColor(color)
        }
    }
}

/// 頁尾：「Powered by ＋ INTENTION 字標」左、*talky 右。每個露臉面都用這一列。
struct PoweredBy: View {
    var showLogotype = true
    var body: some View {
        HStack(spacing: NeuSpace.sm) {
            Text("Powered by").font(NeuFont.ui(NeuType.micro)).foregroundColor(Neu.inkSoft)
            IntentionWordmark(height: 8.5)
            Spacer(minLength: 0)
            if showLogotype { TalkyLogotype(height: 15) }
        }
    }
}

// MARK: - 元件

/// 深炭錨圓鈕：全畫面唯一高對比元素，只給錄音主行動
struct NeuAnchorButton: View {
    enum Glyph { case dot, square }
    var glyph: Glyph = .dot
    var size: CGFloat = 108
    var action: () -> Void = {}

    @State private var pressed = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Neu.material)
                    .frame(width: size + 18, height: size + 18)
                    .shadow(color: Neu.light.opacity(pressed ? 0.4 : 0.95), radius: 8, x: -5, y: -5)
                    .shadow(color: Neu.shade.opacity(pressed ? 0.2 : 0.5), radius: 9, x: 5, y: 5)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Neu.keyFace, Neu.keyFaceDeep],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [Neu.light.opacity(0.85), Neu.shade.opacity(0.45)],
                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .shadow(color: Neu.shade.opacity(0.38), radius: 4, x: 2, y: 3)
                switch glyph {
                case .dot:
                    Circle().fill(Neu.inkStrong)
                        .frame(width: size * 0.125, height: size * 0.125)
                case .square:
                    RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                        .fill(Neu.inkStrong)
                        .frame(width: size * 0.195, height: size * 0.195)
                }
            }
            .scaleEffect(pressed ? 0.975 : (hovering ? 1.012 : 1))
            .animation(NeuMotion.press, value: pressed)
            .animation(NeuMotion.press, value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

/// 寬膠囊主鈕；leadingAnchor = 左端那顆深炭圓（＝這顆鈕會開始錄音）
struct NeuCapsuleButton: View {
    let title: String
    var leadingAnchor: Bool = false
    var height: CGFloat = 46
    var enabled: Bool = true
    var action: () -> Void = {}

    @State private var pressed = false
    @State private var hovering = false

    var body: some View {
        Button(action: { if enabled { action() } }) {
            ZStack {
                Text(title)
                    .font(NeuFont.ui(NeuType.body))
                    .foregroundColor(enabled ? Neu.inkStrong : Neu.inkSoft)
                if leadingAnchor {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Neu.keyFace, Neu.keyFaceDeep],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .overlay(
                                    Circle().stroke(Neu.light.opacity(0.7), lineWidth: 0.8)
                                )
                            Circle().fill(Neu.inkStrong)
                                .frame(width: (height - 16) * 0.28, height: (height - 16) * 0.28)
                        }
                        .frame(width: height - 16, height: height - 16)
                        .padding(.leading, 8)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .neuRaised(NeuRadius.pill, lift: 0.85, pressed: pressed)
            .brightness(hovering && !pressed && enabled ? 0.012 : 0)
            .animation(NeuMotion.press, value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if enabled { pressed = true } }
                .onEnded { _ in pressed = false }
        )
    }
}

/// 小圓形圖示鈕；on＝開關鈕的「開」狀態：常亮墨色＋凹陷（已按下）
struct NeuIconButton: View {
    let systemName: String
    var size: CGFloat = 22
    var on: Bool = false
    var action: () -> Void = {}
    @State private var pressed = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(hovering || on ? Neu.inkStrong : Neu.inkMid)
                .frame(width: size, height: size)
                .background {
                    if pressed || on {
                        Circle().fill(Neu.material)
                            .neuDebossed(NeuRadius.pill, depth: 0.7)
                    } else {
                        Circle().fill(Neu.material)
                            .shadow(color: Neu.light.opacity(0.95), radius: 2.5, x: -1.5, y: -1.5)
                            .shadow(color: Neu.shade.opacity(0.45), radius: 3, x: 1.5, y: 1.5)
                    }
                }
                .animation(NeuMotion.press, value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

/// 統一返回頭列
struct NeuBackHeader: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: NeuSpace.md) {
            NeuIconButton(systemName: "chevron.left", size: 26) { onBack() }
            Text(title)
                .font(NeuFont.ui(NeuType.title, true))
                .foregroundColor(Neu.inkStrong)
                .lineLimit(1)
            Spacer()
        }
    }
}

/// 小膠囊
struct NeuChip: View {
    let title: String
    var enabled: Bool = true
    var action: () -> Void = {}
    @State private var pressed = false
    @State private var hovering = false

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(NeuFont.ui(NeuType.caption))
                .foregroundColor(enabled ? Neu.inkStrong : Neu.inkSoft)
                .padding(.horizontal, NeuSpace.md)
                .frame(height: 34)
                .neuRaised(NeuRadius.pill, lift: 0.6, pressed: pressed)
                .brightness(hovering && !pressed && enabled ? 0.012 : 0)
                .animation(NeuMotion.press, value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if enabled { pressed = true } }
                .onEnded { _ in pressed = false }
        )
    }
}

/// 狀態小標（只用墨三階，不用彩色）：ready＝深墨實心點、pending＝中灰、missing＝淺灰空心
struct NeuStatusTag: View {
    enum Level { case ready, pending, missing }
    let level: Level
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(level == .missing ? Neu.inkSoft : .clear, lineWidth: 1)
                .background(
                    Circle().fill(
                        level == .ready ? Neu.inkStrong : (level == .pending ? Neu.inkMid : .clear)))
                .frame(width: 7, height: 7)
            Text(text).font(NeuFont.ui(NeuType.micro))
                .foregroundColor(level == .missing ? Neu.inkSoft : Neu.inkMid)
        }
    }
}

/// 分段選擇：整條是凹陷容器，選中那格凸起
struct NeuSegmented: View {
    let items: [String]
    @Binding var selection: Int
    var height: CGFloat = 40
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let on = i == selection
                Text(items[i])
                    .font(NeuFont.ui(NeuType.caption, on))
                    .foregroundColor(on ? Neu.inkStrong : Neu.inkMid)
                    .frame(maxWidth: .infinity)
                    .frame(height: height - 8)
                    .background {
                        if on {
                            Capsule()
                                .fill(Neu.material)
                                .shadow(color: Neu.light.opacity(0.95), radius: 3, x: -2, y: -2)
                                .shadow(color: Neu.shade.opacity(0.42), radius: 4, x: 2, y: 2)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(NeuMotion.ui) { selection = i } }
            }
        }
        .padding(4)
        .frame(height: height)
        .neuDebossed(NeuRadius.pill, depth: 0.85)
    }
}

/// 凹槽：音量條與進度條共用。fill 0…1；nil＝不確定型（一段在跑）
struct NeuGroove: View {
    var fill: CGFloat?
    var height: CGFloat = 16
    @State private var drift: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inner = max(2, height - 7)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Neu.material)
                    .frame(width: max(inner, w * max(0.04, min(1, fill ?? 0.32)) - 6), height: inner)
                    .shadow(color: Neu.light.opacity(0.9), radius: 2.5, x: -1.5, y: -1.5)
                    .shadow(color: Neu.shade.opacity(0.4), radius: 3, x: 1.5, y: 1.5)
                    .padding(.leading, 3.5)
                    .offset(x: fill == nil ? drift * (w * 0.62) : 0)
                    .animation(fill == nil ? nil : .linear(duration: 0.08), value: fill)
            }
            .frame(width: w, height: height, alignment: .leading)
            .onAppear { setDrift(running: fill == nil) }
            .onDisappear { setDrift(running: false) }
            // 同一顆 NeuGroove 從「不確定型」換成有進度值時，SwiftUI 可能沿用同一個 view
            // identity——不明講就停不下來，動畫看不見卻照跑（見下面 setDrift 的註解）。
            .onChange(of: fill == nil) { _, indeterminate in setDrift(running: indeterminate) }
        }
        .frame(height: height)
        .neuDebossed(NeuRadius.pill, depth: 0.9)
    }

    /// `.repeatForever` 不會自己結束：view 只是被藏起來（視窗 orderOut、或被 if 換掉）時，
    /// 動畫仍掛在 view graph 上，每個顯示週期都逼一次重排＝主執行緒永久空轉。
    /// 停的方法是用一個有限動畫覆寫同一個屬性，把它從 graph 上換掉。
    private func setDrift(running: Bool) {
        if running {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { drift = 1 }
        } else {
            withAnimation(.linear(duration: 0.01)) { drift = 0 }
        }
    }
}

/// 凹陷卡：內容容器
struct NeuInset<Content: View>: View {
    var radius: CGFloat = NeuRadius.card
    @ViewBuilder var content: Content
    var body: some View {
        content.neuDebossed(radius, depth: 0.95)
    }
}

/// 處理中的階段列：done＝打勾且字變淡；active＝米字呼吸
struct NeuStageRow: View {
    let title: String
    var done: Bool = false
    var active: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(NeuFont.ui(NeuType.body, active))
                .foregroundColor(done ? Neu.inkSoft : Neu.inkStrong)
            Spacer()
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neu.inkStrong)
            } else if active {
                TalkyMark(mode: .listening, size: 9)
            }
        }
        .padding(.horizontal, NeuSpace.lg)
        .frame(height: 42)
        .neuDebossed(NeuRadius.pill, depth: done ? 0.7 : 0.95)
    }
}

/// 一行說明字（micro，中灰；軟浮雕低對比→不用淺灰）
struct NeuNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(NeuFont.ui(NeuType.micro))
            .foregroundColor(Neu.inkMid)
            .fixedSize(horizontal: false, vertical: true)
    }
}
