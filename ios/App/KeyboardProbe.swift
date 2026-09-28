// KeyboardProbe — 開發用：模擬器裡直接叫出 Talky 鍵盤截圖（不用進設定切鍵盤）
//
// 用法：xcrun simctl launch <裝置> ltd.intention.talky.ios -TalkyKeyboardProbe [talky|system]
// 鍵盤各種狀態：先把想看的 state.json 寫進模擬器的 App Group（Library/state.json），再開探針。
// 只在 DEBUG 版存在，正式版沒有這個畫面。

#if DEBUG
import SwiftUI
import UIKit

struct KeyboardProbeView: View {
    let useTalky: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(useTalky ? "Talky 鍵盤探針" : "原生鍵盤探針").font(.headline)
            ProbeTextView(useTalky: useTalky).frame(height: 140)
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
}

private struct ProbeTextView: UIViewRepresentable {
    let useTalky: Bool

    func makeUIView(context: Context) -> ProbeUITextView {
        let v = ProbeUITextView()
        v.useTalky = useTalky
        v.font = .systemFont(ofSize: 17)
        v.text = "明天見"
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 12
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { v.becomeFirstResponder() }
        return v
    }

    func updateUIView(_ v: ProbeUITextView, context: Context) {}
}

private final class ProbeUITextView: UITextView {
    var useTalky = true

    /// 指定要哪個鍵盤：從已啟用的鍵盤裡挑 Talky（identifier 是私有欄位，只在 DEBUG 用）
    override var textInputMode: UITextInputMode? {
        guard useTalky else { return super.textInputMode }
        let sel = NSSelectorFromString("identifier")
        let modes = UITextInputMode.activeInputModes
        print("PROBE modes:", modes.map { m in m.responds(to: sel) ? (m.value(forKey: "identifier") as? String ?? "?") : "?" })
        let talky = modes.first { m in
            m.responds(to: sel) && ((m.value(forKey: "identifier") as? String)?.contains("talky") ?? false)
        }
        return talky ?? super.textInputMode
    }
}
#endif
