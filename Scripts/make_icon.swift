// 生成菜单栏模板图标：swift Scripts/make_icon.swift Resources/icon.tiff
// 16pt 飞鸟剪影（青鸟）；同时输出 1x 和 2x
import AppKit

let output = CommandLine.arguments[1]

func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

// 各部分分开填充：路径方向不一，合成一条在重叠处会按非零环绕规则镂空
func birdParts() -> [NSBezierPath] {
    let head = NSBezierPath(ovalIn: NSRect(x: 11.5, y: 8.7, width: 3.4, height: 3.4))
    let beak = NSBezierPath()
    beak.move(to: pt(14.2, 11.4)); beak.line(to: pt(15.9, 10.6)); beak.line(to: pt(14.6, 9.6)); beak.close()

    let body = NSBezierPath()
    body.move(to: pt(12.6, 11.9))
    body.curve(to: pt(5.6, 7.9), controlPoint1: pt(10.4, 11.4), controlPoint2: pt(7.6, 9.4))
    body.line(to: pt(0.2, 9.4))
    body.line(to: pt(4.6, 6.9))
    body.line(to: pt(1.0, 3.6))
    body.line(to: pt(6.4, 6.4))
    body.curve(to: pt(13.4, 8.8), controlPoint1: pt(8.6, 6.6), controlPoint2: pt(11.4, 7.4))
    body.close()

    let upperWing = NSBezierPath()
    upperWing.move(to: pt(11.4, 10.8))
    upperWing.curve(to: pt(3.4, 15.8), controlPoint1: pt(11.0, 14.4), controlPoint2: pt(7.0, 16.2))
    upperWing.curve(to: pt(7.6, 9.4), controlPoint1: pt(6.0, 14.4), controlPoint2: pt(7.0, 12.0))
    upperWing.close()

    let lowerWing = NSBezierPath()
    lowerWing.move(to: pt(10.6, 8.0))
    lowerWing.curve(to: pt(10.8, 0.4), controlPoint1: pt(12.6, 6.0), controlPoint2: pt(12.4, 2.6))
    lowerWing.curve(to: pt(7.8, 7.2), controlPoint1: pt(10.0, 3.0), controlPoint2: pt(8.8, 5.6))
    lowerWing.close()
    return [head, beak, body, upperWing, lowerWing]
}

func makeRep(scale: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(16 * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 16, height: 16)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.black.setFill()
    birdParts().forEach { $0.fill() }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: 16, height: 16))
image.addRepresentation(makeRep(scale: 1))
image.addRepresentation(makeRep(scale: 2))
try! image.tiffRepresentation!.write(to: URL(fileURLWithPath: output))
