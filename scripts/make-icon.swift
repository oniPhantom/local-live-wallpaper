import AppKit

// アプリアイコン生成(一度だけ実行して icon.icns を作る):
//   swift scripts/make-icon.swift \
//     && iconutil -c icns icon.iconset -o Sources/LiveWallpaper/icon.icns \
//     && cp icon.iconset/icon_256x256.png docs/assets/icon.png \
//     && rm -r icon.iconset

func draw(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // 背景: 角丸の夜空グラデーション(壁紙モチーフ)
    let inset = s * 0.04
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.14, alpha: 1),
    ])?.draw(in: bg, angle: -70)

    bg.setClip()

    // オーロラ: 上空に斜めの淡い光の帯
    for (offset, alpha) in [(0.00, 0.22), (0.10, 0.14)] {
        let aurora = NSBezierPath()
        let baseY = rect.maxY - rect.height * (0.18 + CGFloat(offset))
        aurora.move(to: NSPoint(x: rect.minX, y: baseY - s * 0.10))
        aurora.curve(
            to: NSPoint(x: rect.maxX, y: baseY + s * 0.06),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.35, y: baseY + s * 0.14),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.65, y: baseY - s * 0.12))
        aurora.line(to: NSPoint(x: rect.maxX, y: baseY + s * 0.20))
        aurora.curve(
            to: NSPoint(x: rect.minX, y: baseY + s * 0.04),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.65, y: baseY + s * 0.02),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.35, y: baseY + s * 0.28))
        aurora.close()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.30, green: 0.90, blue: 0.75, alpha: CGFloat(alpha)),
            NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.00, alpha: CGFloat(alpha) * 0.5),
        ])?.draw(in: aurora, angle: 0)
    }

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

    // 山のシルエット(壁紙感): 底辺に接地した三角形2つ。奥は淡く、手前は濃く
    let backMountain = NSBezierPath()
    backMountain.move(to: NSPoint(x: rect.minX - rect.width * 0.10, y: rect.minY))
    backMountain.line(to: NSPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.44))
    backMountain.line(to: NSPoint(x: rect.minX + rect.width * 0.72, y: rect.minY))
    backMountain.close()
    NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.48, alpha: 1).setFill()
    backMountain.fill()

    let frontMountain = NSBezierPath()
    frontMountain.move(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY))
    frontMountain.line(to: NSPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.34))
    frontMountain.line(to: NSPoint(x: rect.maxX + rect.width * 0.12, y: rect.minY))
    frontMountain.close()
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.22, alpha: 1).setFill()
    frontMountain.fill()

    // 月のように浮かぶ再生トライアングル(バッジなし・シアン発光)
    let glow = NSShadow()
    glow.shadowColor = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.95, alpha: 0.85)
    glow.shadowBlurRadius = s * 0.06
    glow.set()

    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: s * 0.40, y: s * 0.42))
    tri.line(to: NSPoint(x: s * 0.40, y: s * 0.70))
    tri.line(to: NSPoint(x: s * 0.66, y: s * 0.56))
    tri.close()
    tri.lineJoinStyle = .round
    tri.lineWidth = s * 0.045
    NSColor(calibratedRed: 0.55, green: 0.92, blue: 1.00, alpha: 1).setStroke()
    tri.stroke()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.55, green: 0.92, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.31, green: 0.49, blue: 1.00, alpha: 1),
    ])?.draw(in: tri, angle: -80)

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
