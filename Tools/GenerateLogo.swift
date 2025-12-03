import Foundation
import AppKit

let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("public")
let outputFile = outputDir.appendingPathComponent("logo.png")

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let canvasW = 1024
let canvasH = 1024
let margin: CGFloat = 140

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasW, pixelsHigh: canvasH, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fputs("Failed to create bitmap\n", stderr)
    exit(1)
}

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create context\n", stderr)
    exit(1)
}

NSGraphicsContext.current = ctx
NSGraphicsContext.current?.imageInterpolation = .high

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasW, height: canvasH)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

func buildString(size: CGFloat) -> NSMutableAttributedString {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let s = NSMutableAttributedString(string: "ClipCat", attributes: [.font: font, .paragraphStyle: paragraph])
    s.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: NSRange(location: 0, length: 4))
    s.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: 4, length: 3))
    return s
}

var fontSize: CGFloat = 300
var attr = buildString(size: fontSize)
var bounds = attr.boundingRect(with: NSSize(width: CGFloat(canvasW), height: CGFloat(canvasH)), options: [.usesLineFragmentOrigin, .usesFontLeading])

let targetW = CGFloat(canvasW) - margin * 2
let targetH = CGFloat(canvasH) - margin * 2

while (bounds.width > targetW || bounds.height > targetH) && fontSize > 12 {
    fontSize -= 4
    attr = buildString(size: fontSize)
    bounds = attr.boundingRect(with: NSSize(width: CGFloat(canvasW), height: CGFloat(canvasH)), options: [.usesLineFragmentOrigin, .usesFontLeading])
}

let drawRect = NSRect(x: (CGFloat(canvasW) - bounds.width) / 2, y: (CGFloat(canvasH) - bounds.height) / 2, width: bounds.width, height: bounds.height)
attr.draw(in: drawRect)

ctx.flushGraphics()
NSGraphicsContext.current = nil

if let pngData = rep.representation(using: .png, properties: [:]) {
    do {
        try pngData.write(to: outputFile)
        fputs("Generated: \(outputFile.path)\n", stdout)
        exit(0)
    } catch {
        fputs("Failed to write file: \(error)\n", stderr)
        exit(1)
    }
} else {
    fputs("Failed to create PNG data\n", stderr)
    exit(1)
}
