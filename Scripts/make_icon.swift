// 生成菜单栏模板图标：swift Scripts/make_icon.swift Resources/icon.tiff
// 16pt 实心圆，字镂空；同时输出 1x 和 2x
import AppKit

let output = CommandLine.arguments[1]

func makeRep(scale: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(16 * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 16, height: 16)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
    context.compositingOperation = .destinationOut
    let text = NSAttributedString(string: "译", attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.black,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: 16, height: 16))
image.addRepresentation(makeRep(scale: 1))
image.addRepresentation(makeRep(scale: 2))
try! image.tiffRepresentation!.write(to: URL(fileURLWithPath: output))
