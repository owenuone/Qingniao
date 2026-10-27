// 生成菜单栏模板图标：swift Scripts/make_icon.swift Resources/icon.tiff
import AppKit

let output = CommandLine.arguments[1]
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: 16, height: 16)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let text = NSAttributedString(string: "译", attributes: [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor.black,
])
let size = text.size()
text.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2))
NSGraphicsContext.restoreGraphicsState()
try! rep.tiffRepresentation!.write(to: URL(fileURLWithPath: output))
