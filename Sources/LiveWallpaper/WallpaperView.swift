import Cocoa

// 再生失敗時などに表示するフォールバックのアニメ壁紙(星空 + オーロラ + グリッド)
final class WallpaperView: NSView {
    private var timer: Timer?
    private let start = CACurrentMediaTime()
    private let starCount = 90

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = CACurrentMediaTime() - start
        let rect = bounds
        let cg = NSGraphicsContext.current?.cgContext

        NSColor(calibratedRed: 0.005, green: 0.008, blue: 0.018, alpha: 1).setFill()
        rect.fill()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.01, green: 0.015, blue: 0.04, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.025, blue: 0.09, alpha: 1),
            NSColor(calibratedRed: 0.005, green: 0.008, blue: 0.018, alpha: 1)
        ])?.draw(in: rect, angle: 45 + CGFloat(sin(t * 0.03)) * 12)

        drawStars(in: rect, time: t)
        drawAurora(in: rect, time: t)
        drawOrbitalGlow(in: rect, time: t)
        drawPerspectiveGrid(in: rect, time: t)

        cg?.saveGState()
        cg?.setBlendMode(.multiply)
        NSGradient(colors: [
            NSColor(calibratedWhite: 0, alpha: 0.78),
            NSColor(calibratedWhite: 0, alpha: 0.10),
            NSColor(calibratedWhite: 0, alpha: 0.82)
        ])?.draw(in: rect, relativeCenterPosition: NSPoint(x: 0, y: 0))
        cg?.restoreGState()

        NSColor(calibratedWhite: 1, alpha: 0.018).setFill()
        for y in stride(from: 0, to: Int(rect.height), by: 5) {
            NSBezierPath(rect: NSRect(x: 0, y: CGFloat(y), width: rect.width, height: 1)).fill()
        }
    }

    private func drawStars(in rect: NSRect, time: TimeInterval) {
        for i in 0..<starCount {
            let seed = Double(i)
            let x = CGFloat((sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude) * rect.width
            let y = CGFloat((sin(seed * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1).magnitude) * rect.height
            let pulse = 0.25 + 0.75 * CGFloat(pow(max(0, sin(time * 0.7 + seed)), 2))
            let size = CGFloat(0.8 + fmod(seed, 3)) * pulse

            NSColor(calibratedRed: 0.72, green: 0.92, blue: 1, alpha: 0.20 + 0.38 * pulse).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private func drawAurora(in rect: NSRect, time: TimeInterval) {
        let colors = [
            NSColor(calibratedRed: 0.04, green: 0.96, blue: 0.82, alpha: 0.18),
            NSColor(calibratedRed: 0.32, green: 0.30, blue: 1.00, alpha: 0.16),
            NSColor(calibratedRed: 1.00, green: 0.20, blue: 0.58, alpha: 0.12)
        ]

        for band in 0..<4 {
            let path = NSBezierPath()
            let yBase = rect.midY + rect.height * CGFloat(0.08 + Double(band) * 0.035)
            path.move(to: NSPoint(x: -rect.width * 0.1, y: yBase))

            for step in 0...7 {
                let x = rect.width * CGFloat(Double(step) / 6.0) - rect.width * 0.08
                let wave = sin(time * (0.22 + Double(band) * 0.025) + Double(step) * 0.9 + Double(band))
                let y = yBase + CGFloat(wave) * rect.height * CGFloat(0.05 + Double(band) * 0.006)
                path.line(to: NSPoint(x: x, y: y))
            }

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 38 + CGFloat(band) * 10
            shadow.shadowColor = colors[band % colors.count]
            shadow.set()
            colors[band % colors.count].setStroke()
            path.lineWidth = 36 + CGFloat(band) * 7
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawOrbitalGlow(in rect: NSRect, time: TimeInterval) {
        let center = NSPoint(
            x: rect.midX + CGFloat(cos(time * 0.08)) * rect.width * 0.08,
            y: rect.midY + CGFloat(sin(time * 0.06)) * rect.height * 0.05
        )

        for i in 0..<5 {
            let scale = CGFloat(0.36 + Double(i) * 0.08)
            let w = rect.width * scale
            let h = w * CGFloat(0.18 + Double(i) * 0.018)
            let oval = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)

            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: CGFloat(12 + i * 13) + CGFloat(sin(time * 0.1)) * 10)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()

            NSColor(calibratedRed: 0.40, green: 0.90, blue: 1.00, alpha: 0.08).setStroke()
            let path = NSBezierPath(ovalIn: oval)
            path.lineWidth = 1.2
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawPerspectiveGrid(in rect: NSRect, time: TimeInterval) {
        let horizon = rect.height * 0.30
        let bottom = rect.height
        let color = NSColor(calibratedRed: 0.12, green: 0.95, blue: 1, alpha: 0.14)
        color.setStroke()

        for i in -7...7 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX + CGFloat(i) * rect.width * 0.035, y: horizon))
            path.line(to: NSPoint(x: rect.midX + CGFloat(i) * rect.width * 0.16, y: bottom))
            path.lineWidth = 1
            path.stroke()
        }

        for i in 0..<12 {
            let progress = CGFloat(i) / 12
            let y = horizon + pow(progress, 2.1) * (bottom - horizon)
            let offset = CGFloat(fmod(time * 18, 36))
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y + offset))
            path.line(to: NSPoint(x: rect.width, y: y + offset))
            path.lineWidth = 1
            path.stroke()
        }
    }
}
