import AppKit

// アプリアイコン生成(一度だけ実行して icon.icns を作る):
//   swift scripts/make-icon.swift && iconutil -c icns icon.iconset -o LiveWallpaper/icon.icns && rm -r icon.iconset

func draw(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // 背景: 角丸ダークグラデーション
    let inset = s * 0.04
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.06, alpha: 1),
    ])?.draw(in: bg, angle: -70)

    // うっすら星
    for i in 0..<24 {
        let seed = Double(i)
        let x = CGFloat((sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude)
        let y = CGFloat((sin(seed * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1).magnitude)
        let px = rect.minX + rect.width * x
        let py = rect.minY + rect.height * (0.55 + y * 0.4)
        let r = s * 0.004 * (1 + CGFloat(i % 3))
        NSColor(calibratedWhite: 1, alpha: 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: px, y: py, width: r, height: r)).fill()
    }

    // 赤い再生バッジ + 白い三角
    let badge = NSRect(x: s * 0.26, y: s * 0.32, width: s * 0.48, height: s * 0.36)
    let badgePath = NSBezierPath(roundedRect: badge, xRadius: s * 0.10, yRadius: s * 0.10)
    NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.13, alpha: 1).setFill()
    badgePath.fill()

    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: s * 0.44, y: s * 0.40))
    tri.line(to: NSPoint(x: s * 0.44, y: s * 0.60))
    tri.line(to: NSPoint(x: s * 0.61, y: s * 0.50))
    tri.close()
    NSColor.white.setFill()
    tri.fill()

    // 下部の地平線ライン(壁紙感)
    let line = NSBezierPath()
    line.move(to: NSPoint(x: rect.minX + s * 0.10, y: s * 0.22))
    line.line(to: NSPoint(x: rect.maxX - s * 0.10, y: s * 0.22))
    line.lineWidth = s * 0.012
    NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.95, alpha: 0.55).setStroke()
    line.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("png conversion failed: \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = "icon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(draw(size: base), to: "\(outDir)/icon_\(base)x\(base).png")
    writePNG(draw(size: base * 2), to: "\(outDir)/icon_\(base)x\(base)@2x.png")
}
print("generated \(outDir)")
