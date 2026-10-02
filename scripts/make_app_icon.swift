// Regenerate: swiftc -O scripts/make_app_icon.swift -o /tmp/make_app_icon && /tmp/make_app_icon Sources/Fluid/Assets.xcassets/AppIcon.appiconset
// Draws the MouthKeys app icon, the pirate keycap grin (DESIGN.md §17, prototypes/signal/icon-grin.html): an ink
// tile, full-bleed, and a grin of white square-ended teeth on a 64-unit grid, the trace mirrored and split by the
// bite, with one lower tooth right of centre in orange (the gold tooth). The detail follows the pixel count:
//   256 px and up   seven teeth a jaw, each drawn as a keycap in plan view (top face and chamfers, 0.3 units)
//   128 px          the same keycaps at double weight (0.6 units), so they still read in the Dock
//   33 to 64 px     the small master: five teeth a jaw, plain
//   32 px and 16 px the small master placed on whole pixels
import AppKit

let out = CommandLine.arguments[1]
let ink = CGColor(srgbRed: 0x11 / 255.0, green: 0x12 / 255.0, blue: 0x14 / 255.0, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let orange = CGColor(srgbRed: 1, green: 0x4F / 255.0, blue: 0x1F / 255.0, alpha: 1)

struct Master {
    let teeth: Int, width: CGFloat, pitch: CGFloat, gap: CGFloat, scale: CGFloat, gold: Int
    let upper: [CGFloat], lower: [CGFloat], smile: [CGFloat]
}

let large = Master(teeth: 7, width: 5, pitch: 6.4, gap: 3, scale: 1.15, gold: 4,
                   upper: [5, 8, 9, 9, 9, 8, 5], lower: [4, 7, 9, 9, 9, 7, 4], smile: [-2.5, -1, -0.3, 0, -0.3, -1, -2.5])
let small = Master(teeth: 5, width: 6, pitch: 8, gap: 4, scale: 1.1, gold: 3,
                   upper: [7, 11, 11, 11, 7], lower: [6, 10, 10, 10, 6], smile: [-2, 0, 0, 0, -2])

/// A keycap in plan view inside a tooth: the top face, inset and offset toward the bite, and four chamfer lines.
func keycap(_ ctx: CGContext, _ r: CGRect, upper: Bool, inset: CGFloat, near: CGFloat, far: CGFloat, line: CGFloat, alpha: CGFloat) {
    let i = r.width * inset
    let face = upper
        ? CGRect(x: r.minX + i, y: r.minY + i * near, width: r.width - 2 * i, height: r.height - i * (near + far))
        : CGRect(x: r.minX + i, y: r.minY + i * far, width: r.width - 2 * i, height: r.height - i * (near + far))
    ctx.setStrokeColor(ink.copy(alpha: alpha)!)
    ctx.setLineWidth(line)
    ctx.stroke(face)
    for (a, b) in [(CGPoint(x: r.minX, y: r.minY), CGPoint(x: face.minX, y: face.minY)),
                   (CGPoint(x: r.maxX, y: r.minY), CGPoint(x: face.maxX, y: face.minY)),
                   (CGPoint(x: r.minX, y: r.maxY), CGPoint(x: face.minX, y: face.maxY)),
                   (CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: face.maxX, y: face.maxY))] {
        ctx.strokeLineSegments(between: [a, b])
    }
}

func render(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // SVG coordinates (y down) onto CG (y up).
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(ink)
    ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

    if pixels <= 32 {
        // Whole pixels, drawn in pixels, the outer bites a pixel higher so the bite smiles. 32 px: the small master
        // (five teeth a jaw, 3 px wide on a 4 px pitch, the fourth lower tooth gold). 16 px: four teeth a jaw,
        // 2 px wide on a 3 px pitch, the third lower tooth gold.
        ctx.setShouldAntialias(false)
        let teeth = pixels == 16 ? 4 : 5, w: CGFloat = pixels == 16 ? 2 : 3, p: CGFloat = pixels == 16 ? 3 : 4
        let x0: CGFloat = pixels == 16 ? 2 : 6, bite: CGFloat = pixels == 16 ? 8 : 15, gap: CGFloat = pixels == 16 ? 1 : 2
        let (upIn, upOut, loIn, loOut): (CGFloat, CGFloat, CGFloat, CGFloat) = pixels == 16 ? (4, 3, 3, 2) : (6, 4, 6, 3)
        let gold = pixels == 16 ? 2 : 3
        for i in 0..<teeth {
            let outer = i == 0 || i == teeth - 1, x = x0 + CGFloat(i) * p, lift: CGFloat = outer ? 1 : 0
            let up = outer ? upOut : upIn, lo = outer ? loOut : loIn
            ctx.setFillColor(white)
            ctx.fill(CGRect(x: x, y: bite - lift - up, width: w, height: up))
            ctx.setFillColor(i == gold ? orange : white)
            ctx.fill(CGRect(x: x, y: bite + gap - lift, width: w, height: lo))
        }
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    let m = pixels >= 128 ? large : small
    let unit = CGFloat(pixels) / 64
    ctx.scaleBy(x: unit, y: unit)
    // The mark is scaled about the tile centre so it carries the shipping icon's weight.
    ctx.translateBy(x: 32, y: 32)
    ctx.scaleBy(x: m.scale, y: m.scale)
    ctx.translateBy(x: -32, y: -32)
    let x0 = 32 - (CGFloat(m.teeth - 1) * m.pitch + m.width) / 2, mid: CGFloat = 32
    for i in 0..<m.teeth {
        let x = x0 + CGFloat(i) * m.pitch
        let up = CGRect(x: x, y: mid - m.gap / 2 - m.upper[i] + m.smile[i], width: m.width, height: m.upper[i])
        let lo = CGRect(x: x, y: mid + m.gap / 2 + m.smile[i], width: m.width, height: m.lower[i])
        ctx.setFillColor(white)
        ctx.fill(up)
        ctx.setFillColor(i == m.gold ? orange : white)
        ctx.fill(lo)
        if pixels >= 256 {
            keycap(ctx, up, upper: true, inset: 0.22, near: 0.6, far: 1.4, line: 0.3, alpha: 0.55)
            keycap(ctx, lo, upper: false, inset: 0.22, near: 0.6, far: 1.4, line: 0.3, alpha: 0.55)
        } else if pixels >= 128 {
            keycap(ctx, up, upper: true, inset: 0.24, near: 0.5, far: 1.5, line: 0.6, alpha: 0.8)
            keycap(ctx, lo, upper: false, inset: 0.24, near: 0.5, far: 1.5, line: 0.6, alpha: 0.8)
        }
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

// (file, points, scale)
let slots: [(String, Int, Int)] = [
    ("icon-16@1x.png", 16, 1), ("icon-16@2x.png", 16, 2), ("icon-32@1x.png", 32, 1), ("icon-32@2x.png", 32, 2),
    ("icon-128@1x.png", 128, 1), ("icon-128@2x.png", 128, 2), ("icon-256@1x.png", 256, 1), ("icon-256@2x.png", 256, 2),
    ("icon-512@1x.png", 512, 1), ("icon-512@2x.png", 512, 2),
]
for (file, points, scale) in slots {
    let pixels = points * scale
    try! render(pixels: pixels).write(to: URL(fileURLWithPath: out).appendingPathComponent(file))
    let detail = pixels >= 256 ? "keycaps" : pixels >= 128 ? "keycaps, heavy" : pixels > 32 ? "small master" : "pixel master"
    print(file, pixels, detail)
}
