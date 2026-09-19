// make-icon.swift — 畫 Talky 的 app 圖示（1024×1024 PNG）
// 用法：swift scripts/make-icon.swift <輸出.png>
// 深色軟浮雕材料的圓角方（#2B2D33）＋白色六臂圓頭米字（Talky 的 Logo 形狀，跟 app 內 TalkyMarkShape 同一套幾何）。

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// 滿版、不留邊：macOS 26 會自己套系統的圓角遮罩，留邊的舊式圖示會被塞進一塊白底板（Dock 上變成白框裡一顆小黑方）；
// macOS 14／15 不套遮罩，所以這裡自己畫標準比例的圓角（22.37%）。
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237)
NSGradient(
    starting: NSColor(calibratedRed: 0.196, green: 0.204, blue: 0.227, alpha: 1),   // #32343A 上緣稍亮
    ending: NSColor(calibratedRed: 0.145, green: 0.153, blue: 0.176, alpha: 1)      // #25272D
)?.draw(in: path, angle: -90)
NSColor(calibratedRed: 0.30, green: 0.31, blue: 0.34, alpha: 0.9).setStroke()
path.lineWidth = size * 0.004
path.stroke()

// 六臂米字：三根圓頭長條，各轉 60°
let c = NSPoint(x: size / 2, y: size / 2)
let r = size * 0.29          // 臂長（半徑；滿版後略放大）
let w = r * 0.42             // 臂厚
NSColor.white.setFill()
for k in 0..<3 {
    let t = NSAffineTransform()
    t.translateX(by: c.x, yBy: c.y)
    t.rotate(byDegrees: CGFloat(k) * 60 + 90)
    let bar = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -r, width: w, height: 2 * r), xRadius: w / 2, yRadius: w / 2)
    bar.transform(using: t as AffineTransform)
    bar.fill()
}

img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
try? png.write(to: URL(fileURLWithPath: out))
print("icon → \(out)")
