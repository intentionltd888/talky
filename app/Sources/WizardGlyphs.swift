// WizardGlyphs — 精靈用的圖示化操作說明（0.1.3：操作說明盡量圖像化，小字沒人會看）
//
// 三個零件：
//   Keycap／DoubleKey：畫一顆鍵帽（⌘／⌥／fn），兩顆並排＝「連按兩下」——不用文字解釋鍵盤在哪
//   StepFlow：圖示 → 圖示 → 圖示，底下各一個 2–4 字的動作，取代「你要做的 1-2-3」
//   BrainChoiceCard：整理方式的兩張大卡（用我的訂閱／用本機模型），並排、可點、選中凹下去
// 軟浮雕定則：可點物凸起、選中凹陷；文字 ≥ body 級，不用 micro 小字講操作。

import AppKit
import SwiftUI

/// 一顆鍵帽
struct Keycap: View {
    let label: String
    var size: CGFloat = 34
    var body: some View {
        Text(label)
            .font(NeuFont.mark(size * 0.42, true))
            .foregroundColor(Neu.inkStrong)
            .frame(width: size * 1.15, height: size)
            .neuRaised(size * 0.26, lift: 0.5)
    }
}

/// 兩顆鍵帽並排＝連按兩下
struct DoubleKey: View {
    let label: String
    var size: CGFloat = 34
    var body: some View {
        HStack(spacing: 4) {
            Keycap(label: label, size: size)
            Keycap(label: label, size: size)
        }
    }
}

/// 一步：圖（SF Symbol 或自訂 view）＋底下 2–4 字
struct GlyphStep<G: View>: View {
    let glyph: G
    let label: String
    init(label: String, @ViewBuilder glyph: () -> G) {
        self.label = label
        self.glyph = glyph()
    }
    var body: some View {
        VStack(spacing: NeuSpace.sm) {
            glyph.frame(height: 44)
            Text(label).font(NeuFont.ui(NeuType.body, true)).foregroundColor(Neu.inkStrong)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// SF Symbol 版的一步（凹圓底＋符號）
struct SymbolStep: View {
    let symbol: String
    let label: String
    var body: some View {
        GlyphStep(label: label) {
            ZStack {
                Circle().fill(Neu.material).frame(width: 44, height: 44).neuDebossed(22, depth: 0.7)
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).foregroundColor(Neu.inkStrong)
            }
        }
    }
}

/// 圖示 → 圖示 → 圖示：中間細箭頭
struct StepFlow<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(alignment: .top, spacing: NeuSpace.sm) { content }
            .padding(.vertical, NeuSpace.md)
    }
}

struct FlowArrow: View {
    var body: some View {
        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundColor(Neu.inkSoft)
            .frame(height: 44)
    }
}

/// 整理方式的大卡：並排兩張，可點；選中＝凹＋勾，未選＝凸
struct BrainChoiceCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let status: String
    let statusLevel: NeuStatusTag.Level
    /// 一句白話建議（訂閱整理得比較好、本機模型差一點但不用帳號）
    var advice: String = ""
    let selected: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: NeuSpace.sm) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundColor(Neu.inkStrong)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundColor(Neu.inkStrong)
                    }
                }
                Text(title).font(NeuFont.ui(NeuType.title, true)).foregroundColor(Neu.inkStrong)
                Text(subtitle).font(NeuFont.ui(NeuType.caption)).foregroundColor(Neu.inkMid)
                    .fixedSize(horizontal: false, vertical: true)
                NeuStatusTag(level: statusLevel, text: status)
                if !advice.isEmpty {
                    Text(advice).font(NeuFont.ui(NeuType.caption, true)).foregroundColor(Neu.inkStrong)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
            .padding(NeuSpace.md)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .modifier(CardSurface(selected: selected, pressed: pressed))
            .contentShape(RoundedRectangle(cornerRadius: NeuRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .accessibilityLabel((selected ? "已選用 " : "選用 ") + title)
    }
}

private struct CardSurface: ViewModifier {
    let selected: Bool
    let pressed: Bool
    func body(content: Content) -> some View {
        Group {
            if selected {
                content.neuDebossed(NeuRadius.card, depth: 0.95)
            } else {
                content.neuRaised(NeuRadius.card, lift: 0.7, pressed: pressed)
            }
        }
    }
}
