// make-ios-icon.swift — 畫 Talky iPhone 版的 app 圖示（1024×1024、不透明 PNG）
// 用法：swift scripts/make-ios-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
// 跟 Mac 版 scripts/make-icon.swift 同一套：深色軟浮雕材料＋白色六臂圓頭米字（TalkyMarkShape 的幾何）。
// 差別：iOS 自己套圓角遮罩，所以這裡畫滿版正方形、不留邊、不帶透明通道（有 alpha 的圖示會被 App Store 擋）。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// 材料：上緣稍亮的深炭漸層（#32343A → #25272D），同 Mac 版
let grad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(srgbRed: 0.196, green: 0.204, blue: 0.227, alpha: 1),
        CGColor(srgbRed: 0.145, green: 0.153, blue: 0.176, alpha: 1),
    ] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// 六臂米字：三根圓頭長條，各轉 60°
let r = s * 0.29
let w = r * 0.42
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
for k in 0..<3 {
    ctx.saveGState()
    ctx.translateBy(x: s / 2, y: s / 2)
    ctx.rotate(by: CGFloat(k) * .pi / 3 + .pi / 2)
    let bar = CGPath(
        roundedRect: CGRect(x: -w / 2, y: -r, width: w, height: 2 * r), cornerWidth: w / 2,
        cornerHeight: w / 2, transform: nil)
    ctx.addPath(bar)
    ctx.fillPath()
    ctx.restoreGState()
}

let img = ctx.makeImage()!
let url = URL(fileURLWithPath: out)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("寫檔失敗：\(out)") }
print("✓ \(out)")
