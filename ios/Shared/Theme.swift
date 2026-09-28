// Theme — Talky 的設計規則（Mac 版 app/Sources/Neu.swift 的 iPhone 移植）＋原生鍵盤灰
//
// 世界觀（Mac 版原文）：整個介面是一塊材料，面板與背景同色，形狀只由「雙向陰影」造出來
// （光源固定左上：亮高光在左上、暗影在右下）。凸起＝可按；凹陷＝容器或已選。
// 主行動鈕的面比材料深一階（不用黑）；介面主體不用藍；身份＝六臂圓頭米字＋*talky 字標＋INTENTION® 字標。
// 基準長相＝3_介面/全介面 候選 0907（U6 深色版；06 淺色跟系統）。
//
// iPhone 版只改一件事（顏色的 tone 對齊 iPhone 原生鍵盤的灰色）：
// 材料色換成原生鍵盤的灰——淺色 #DEDFE4、深色 #1E1F23（iOS 26 原生鍵盤實測；深色剛好＝Mac 版的舞台色），
// 陰影、墨、主行動鈕的面跟著材料重配一階。鍵盤跟系統鍵盤是同一個灰，切過來不會跳色。
// 主 app 與鍵盤共用這一份（鍵盤擴充不能用 UIApplication，這裡也沒用）。

import SwiftUI
import UIKit

// MARK: - 動態色（淺／深各一組，跟系統外觀切換）

func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
}

enum Neu {
    /// 材料本色＝原生鍵盤的灰：面板與背景同一個色，靠陰影分層（面板不得與底不同色）
    static let material = dyn(0xDEDFE4, 0x1E1F23)
    /// 左上高光（深色模式下是一道很淡的亮邊，不是白光暈）
    static let light = dyn(0xFFFFFF, 0x34363D)
    /// 右下影
    static let shade = dyn(0x989BA4, 0x08090B)
    /// 墨三階（軟浮雕天生低對比：正文一律 inkStrong，禁止淺灰壓淺灰）
    static let inkStrong = dyn(0x25272C, 0xE8E9EC)
    static let inkMid = dyn(0x62656D, 0xA6A8B0)
    static let inkSoft = dyn(0x878A92, 0x7E8189)
    /// 主行動鈕的面：比材料深一階（不用黑，質感更好）；深色模式是亮一階
    static let keyFace = dyn(0xD3D5DB, 0x2B2D33)
    static let keyFaceDeep = dyn(0xC7CAD1, 0x222328)
    /// 凹槽裡那條凸起的量：淺色就是材料本色；深色亮一階，不然在炭灰上看不見
    static let groovePill = dyn(0xDEDFE4, 0x33353C)
    /// 出錯（只給一行字用，不做底色）
    static let warn = dyn(0xA8402C, 0xE58A73)
}

enum NeuSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let hero: CGFloat = 32
    static let edge: CGFloat = 20
}

enum NeuType {
    static let hero: CGFloat = 28
    static let title: CGFloat = 18
    static let body: CGFloat = 15
    static let caption: CGFloat = 13
    static let micro: CGFloat = 11
}

enum NeuRadius {
    static let panel: CGFloat = 22
    static let card: CGFloat = 18
    static let key: CGFloat = 12
    static let pill: CGFloat = 999
}

/// 動效只有三個（vault 視覺 DNA recipes-ui §八）：press 按下、ui 狀態改變、pulse 呼吸
enum NeuMotion {
    static let press = Animation.easeOut(duration: 0.14)
    static let ui = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let pulse = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
}

enum NeuFont {
    static func ui(_ size: CGFloat, _ semi: Bool = false) -> Font {
        .system(size: size, weight: semi ? .semibold : .regular)
    }
    static func mark(_ size: CGFloat, _ semi: Bool = true) -> Font {
        .system(size: size, weight: semi ? .semibold : .regular, design: .rounded)
    }
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
        return content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Neu.material)
                .shadow(color: Neu.light.opacity(pressed ? 0.35 : 0.9), radius: blur * 0.5, x: -offset * 0.6, y: -offset * 0.6)
                .shadow(color: Neu.shade.opacity(pressed ? 0.18 : 0.45), radius: blur * 1.15, x: offset, y: offset)
        )
        .scaleEffect(pressed ? 0.985 : 1)
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
                        .shadow(.inner(color: Neu.shade.opacity(0.42 * depth), radius: 4 * depth, x: 2.5 * depth, y: 2.5 * depth))
                        .shadow(.inner(color: Neu.light.opacity(0.95 * depth), radius: 4 * depth, x: -2.5 * depth, y: -2.5 * depth))
                )
        )
    }
}

extension View {
    func neuRaised(_ radius: CGFloat = NeuRadius.card, lift: CGFloat = 1, pressed: Bool = false) -> some View {
        modifier(NeuRaised(radius: radius, lift: lift, pressed: pressed))
    }
    func neuDebossed(_ radius: CGFloat = NeuRadius.card, depth: CGFloat = 1) -> some View {
        modifier(NeuDebossed(radius: radius, depth: depth))
    }
}

/// 按下去：凸起變淺（陷下去一點）；所有凸起的按鈕共用
struct NeuPressStyle: ButtonStyle {
    var radius: CGFloat = NeuRadius.key
    var lift: CGFloat = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .neuRaised(radius, lift: lift, pressed: configuration.isPressed)
            .animation(NeuMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Talky 身份：六臂圓頭米字

/// Talky 的 Logo 形狀：三根圓頭長條各轉 60°＝六臂（app 圖示同一套幾何）
struct TalkyMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * 0.42
        var p = Path()
        for k in 0..<3 {
            let bar = Path(roundedRect: CGRect(x: -w / 2, y: -r, width: w, height: 2 * r), cornerRadius: w / 2)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(k) * .pi / 3)
            p.addPath(bar.applying(t))
        }
        return p
    }
}

/// 米字光點：每畫面恰一顆，只標「正在進行／剛完成」。
/// idle 靜止／listening 呼吸光暈／working 等速旋轉（系統開「減少動態」時不轉只呼吸）／flash 一閃
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
        // 藏起來就當成 idle：呼吸與旋轉都是 repeatForever，不明講會一直重排
        .onDisappear { apply(.idle) }
        .accessibilityHidden(true)
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

// MARK: - 品牌圖（Brand.xcassets；商標，不在 MIT 範圍，見 app/Resources/Brand/TRADEMARK.md）

/// *talky 標準字（圖檔）
struct TalkyLogotype: View {
    var height: CGFloat = 14
    var color: Color = Neu.inkSoft
    var body: some View {
        Image("TalkyLogotype").renderingMode(.template).resizable().scaledToFit()
            .frame(height: height).foregroundStyle(color)
            .accessibilityLabel("Talky")
    }
}

/// INTENTION® 字標（永遠用圖，不打字）
struct IntentionWordmark: View {
    var height: CGFloat = 9
    var color: Color = Neu.inkSoft
    var body: some View {
        Image("IntentionWordmark").renderingMode(.template).resizable().scaledToFit()
            .frame(height: height).foregroundStyle(color)
            .accessibilityLabel("INTENTION")
    }
}

/// 頁尾：「Powered by ＋ INTENTION 字標」左、*talky 右。每個露臉面都用這一列。
struct PoweredBy: View {
    var showLogotype = true
    var body: some View {
        HStack(spacing: NeuSpace.sm) {
            Text("Powered by").font(NeuFont.ui(NeuType.micro)).foregroundStyle(Neu.inkSoft)
            IntentionWordmark(height: 8.5)
            Spacer(minLength: 0)
            if showLogotype { TalkyLogotype(height: 15) }
        }
    }
}

// MARK: - 元件（照 Mac 版 Neu.swift）

/// 錨圓鈕：全畫面唯一高對比元素，只給錄音主行動。圓點＝開始講、方塊＝講完了；
/// 聽的時候外圈跟著音量擴一點（不用顏色，只用形）
struct NeuAnchorFace: View {
    enum Glyph { case dot, square }
    var glyph: Glyph = .dot
    var size: CGFloat = 84
    var level: CGFloat = 0
    var pressed = false
    var dimmed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Neu.material)
                .frame(width: size + 18, height: size + 18)
                .shadow(color: Neu.light.opacity(pressed ? 0.4 : 0.95), radius: 8, x: -5, y: -5)
                .shadow(color: Neu.shade.opacity(pressed ? 0.2 : 0.5), radius: 9, x: 5, y: 5)
            if glyph == .square {
                Circle()
                    .stroke(Neu.inkStrong.opacity(0.16), lineWidth: 1.5)
                    .frame(width: size + 18 + level * 14, height: size + 18 + level * 14)
                    .animation(.easeOut(duration: 0.12), value: level)
            }
            Circle()
                .fill(LinearGradient(colors: [Neu.keyFace, Neu.keyFaceDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [Neu.light.opacity(0.85), Neu.shade.opacity(0.45)], startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: Neu.shade.opacity(0.38), radius: 4, x: 2, y: 3)
            switch glyph {
            case .dot:
                Circle().fill(Neu.inkStrong).frame(width: size * 0.125, height: size * 0.125)
            case .square:
                RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                    .fill(Neu.inkStrong)
                    .frame(width: size * 0.195, height: size * 0.195)
            }
        }
        .frame(width: size + 32, height: size + 32)
        .opacity(dimmed ? 0.5 : 1)
        .scaleEffect(pressed ? 0.975 : 1)
        .animation(NeuMotion.press, value: pressed)
        .contentShape(Circle())
    }
}

/// 錨圓鈕（按鈕版，主 app 用）
struct NeuAnchorButton: View {
    var glyph: NeuAnchorFace.Glyph = .dot
    var size: CGFloat = 84
    var level: CGFloat = 0
    var dimmed = false
    var action: () -> Void = {}
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            NeuAnchorFace(glyph: glyph, size: size, level: level, pressed: pressed, dimmed: dimmed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(glyph == .dot ? "開始講話" : "講完了")
    }
}

/// 寬膠囊鈕（次要行動）
struct NeuCapsuleButton: View {
    let title: String
    var height: CGFloat = 46
    var enabled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(NeuFont.ui(NeuType.body))
                .foregroundStyle(enabled ? Neu.inkStrong : Neu.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(NeuPressStyle(radius: NeuRadius.pill, lift: 0.85))
    }
}

/// 小膠囊
struct NeuChip: View {
    let title: String
    var enabled: Bool = true
    var height: CGFloat = 34
    var action: () -> Void = {}

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(NeuFont.ui(NeuType.caption))
                .foregroundStyle(enabled ? Neu.inkStrong : Neu.inkSoft)
                .padding(.horizontal, NeuSpace.md)
                .frame(height: height)
        }
        .buttonStyle(NeuPressStyle(radius: NeuRadius.pill, lift: 0.6))
    }
}

/// 小圓形圖示鈕（返回頭列用）
struct NeuIconButton: View {
    let systemName: String
    var size: CGFloat = 32
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(Neu.inkStrong)
                .frame(width: size, height: size)
        }
        .buttonStyle(NeuPressStyle(radius: NeuRadius.pill, lift: 0.5))
    }
}

/// 統一返回頭列（設定的各頁用；不用系統導覽列，整頁是同一塊材料）
struct NeuBackHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: NeuSpace.md) {
            NeuIconButton(systemName: "chevron.left") { dismiss() }
            Text(title)
                .font(NeuFont.ui(NeuType.title, true))
                .foregroundStyle(Neu.inkStrong)
                .lineLimit(1)
            Spacer()
        }
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
                .background(Circle().fill(level == .ready ? Neu.inkStrong : (level == .pending ? Neu.inkMid : .clear)))
                .frame(width: 7, height: 7)
            Text(text).font(NeuFont.ui(NeuType.micro))
                .foregroundStyle(level == .missing ? Neu.inkSoft : Neu.inkMid)
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
                    .foregroundStyle(on ? Neu.inkStrong : Neu.inkMid)
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
    var height: CGFloat = 14
    @State private var drift: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inner = max(2, height - 7)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Neu.groovePill)
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
            .onChange(of: fill == nil) { _, indeterminate in setDrift(running: indeterminate) }
        }
        .frame(height: height)
        .neuDebossed(NeuRadius.pill, depth: 0.9)
    }

    /// repeatForever 不會自己結束：用一個有限動畫覆寫同一個屬性才停得下來（Mac 版同一個坑）
    private func setDrift(running: Bool) {
        if running {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { drift = 1 }
        } else {
            withAnimation(.linear(duration: 0.01)) { drift = 0 }
        }
    }
}

/// 一行說明字（micro，中灰；軟浮雕低對比→不用淺灰）
struct NeuNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(NeuFont.ui(NeuType.caption))
            .foregroundStyle(Neu.inkMid)
            .fixedSize(horizontal: false, vertical: true)
    }
}
