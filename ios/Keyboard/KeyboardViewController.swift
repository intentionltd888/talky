// KeyboardViewController — Talky 鍵盤擴充的入口
//
// 鍵盤本身不能開麥克風（iOS 規定），它只做三件事：
// 1. 按麥克風 → 叫主 app 開始聽（主 app 睡著就用 talky://listen 叫醒）
// 2. 顯示即時字幕、整理中
// 3. 字整理好 → 打進游標；可以「復原」或換成「原文」

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.proxy = { [weak self] in self?.textDocumentProxy }
        model.openHostApp = { [weak self] in self?.openHostApp() ?? false }
        model.nextKeyboard = { [weak self] in self?.advanceToNextInputMode() }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        let h = view.heightAnchor.constraint(equalToConstant: KeyboardView.height)
        h.priority = .init(999)
        h.isActive = true
        heightConstraint = h
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if DEBUG && targetEnvironment(simulator)
        // 模擬器開不了「允許完整取用」：開發時只要 App Group 讀得到就當作有開（看各種狀態的長相用）
        let fullAccess = hasFullAccess || Bridge.container != nil
        #else
        let fullAccess = hasFullAccess
        #endif
        model.appear(fullAccess: fullAccess, needsGlobe: needsInputModeSwitchKey)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.disappear()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.returnKeyLabel = Self.label(for: textDocumentProxy.returnKeyType)
    }

    private static func label(for t: UIReturnKeyType?) -> String {
        switch t {
        case .go: return "前往"
        case .search, .google, .yahoo: return "搜尋"
        case .send: return "傳送"
        case .done: return "完成"
        case .next: return "下一個"
        case .join: return "加入"
        default: return "換行"
        }
    }

    /// 鍵盤擴充不能呼叫 UIApplication.shared.open：沿 responder chain 找到 UIApplication 再開（Typeless／Wispr 同招）
    @discardableResult
    private func openHostApp() -> Bool {
        let url = Bridge.listenURL as NSURL
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication, app.responds(to: sel) {
                typealias OpenFn = @convention(c) (
                    NSObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                ) -> Void
                let fn = unsafeBitCast(app.method(for: sel), to: OpenFn.self)
                fn(app, sel, url, NSDictionary(), nil)
                return true
            }
            responder = r.next
        }
        extensionContext?.open(url as URL, completionHandler: nil)
        return false
    }
}
