import AppKit
import CoreGraphics
import Foundation

// Draws the Skill Manager app icon (concept B: puzzle piece + spark) at any
// size, vector-crisp, using Core Graphics. Coordinates are authored on a
// 1024×1024 grid and scaled to the requested pixel size.

let designSize: CGFloat = 1024

func hex(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Classic jigsaw piece: bump on top, notch on the right, straight left/bottom.
func puzzlePath() -> CGPath {
    let p = CGMutablePath()
    let left: CGFloat = 302, right: CGFloat = 722
    let bottom: CGFloat = 356, top: CGFloat = 716
    let r: CGFloat = 58
    let midY = (bottom + top) / 2
    let midX = (left + right) / 2

    p.move(to: CGPoint(x: left, y: bottom))
    p.addLine(to: CGPoint(x: right, y: bottom))
    p.addLine(to: CGPoint(x: right, y: midY - r))
    p.addArc(center: CGPoint(x: right, y: midY), radius: r,
             startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)   // notch (concave)
    p.addLine(to: CGPoint(x: right, y: top))
    p.addLine(to: CGPoint(x: midX + r, y: top))
    p.addArc(center: CGPoint(x: midX, y: top), radius: r,
             startAngle: 0, endAngle: .pi, clockwise: false)             // tab (convex)
    p.addLine(to: CGPoint(x: left, y: top))
    p.closeSubpath()
    return p
}

/// A four-point sparkle centered at (cx, cy).
func sparklePath(cx: CGFloat, cy: CGFloat, outer: CGFloat, inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<8 {
        let radius = i.isMultiple(of: 2) ? outer : inner
        let angle = .pi / 2 + CGFloat(i) * .pi / 4
        let pt = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

func renderPNG(size: Int) -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(size) / designSize
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Rounded-rect background (Big Sur icon grid: 824 content, centered).
    let inset: CGFloat = 100
    let bgRect = CGRect(x: inset, y: inset, width: designSize - inset * 2, height: designSize - inset * 2)
    let bgPath = squirclePath(rect: bgRect, radius: 185)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [hex(255, 138, 91), hex(240, 96, 46)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512, y: bgRect.maxY),
        end: CGPoint(x: 512, y: bgRect.minY),
        options: []
    )
    ctx.restoreGState()

    // Puzzle piece (white).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26,
                  color: CGColor(srgbRed: 0.55, green: 0.16, blue: 0.05, alpha: 0.28))
    ctx.addPath(puzzlePath())
    ctx.setFillColor(hex(255, 255, 255))
    ctx.fillPath()
    ctx.restoreGState()

    // Spark accent (deep orange), tucked inside the piece's lower-right.
    ctx.addPath(sparklePath(cx: 628, cy: 470, outer: 62, inner: 23))
    ctx.setFillColor(hex(232, 88, 38))
    ctx.fillPath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

// Entry point: write a full .iconset directory.
let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let data = renderPNG(size: variant.size)
    try! data.write(to: outDir.appendingPathComponent("\(variant.name).png"))
}

// Also emit a standalone 1024 preview next to the iconset.
let preview = renderPNG(size: 1024)
try! preview.write(to: outDir.deletingLastPathComponent().appendingPathComponent("AppIcon-1024.png"))
print("Wrote iconset to \(outDir.path)")
