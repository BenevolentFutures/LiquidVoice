// Regenerate: swiftc -O scripts/make_app_icon.swift -o /tmp/make_app_icon && /tmp/make_app_icon Sources/Fluid/Assets.xcassets/AppIcon.appiconset
// Draws the Signal app icon, variant A (DESIGN.md §15, prototypes/signal/icon.html): an ink tile,
// full-bleed, five white square-ended bars (6/12/8/12/6 on a 32-unit grid, 2 wide on a 3 pitch)
// and one orange 6 x 6 square; at 32 pt and below, three bars (6/12/6, 3 wide on a 5 pitch).
import AppKit

let out = CommandLine.arguments[1]
let ink = CGColor(srgbRed: 0x11 / 255.0, green: 0x12 / 255.0, blue: 0x14 / 255.0, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let orange = CGColor(srgbRed: 1, green: 0x4F / 255.0, blue: 0x1F / 255.0, alpha: 1)

func render(pixels: Int, small: Bool) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let unit = CGFloat(pixels) / 32
    // SVG coordinates (y down) onto CG (y up).
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: unit, y: -unit)
    ctx.setShouldAntialias(pixels >= 64)
    ctx.setFillColor(ink)
    ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    if pixels == 16 {
        // 16 px: the 32-unit grid falls on half pixels, so the 3-bar master is placed on whole
        // pixels (bars 2 px wide on a 3 px pitch, 4 / 8 / 4 tall, the square 3 px at the tall bar's
        // foot). Undo the unit scale and draw in pixels, y down.
        ctx.scaleBy(x: 1 / unit, y: 1 / unit)
        ctx.setFillColor(white)
        for (x, top, height) in [(2.0, 6.0, 4.0), (5.0, 4.0, 8.0), (8.0, 6.0, 4.0)] {
            ctx.fill(CGRect(x: x, y: top, width: 2, height: height))
        }
        ctx.setFillColor(orange)
        ctx.fill(CGRect(x: 11, y: 9, width: 3, height: 3))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }
    ctx.setFillColor(white)
    let bars: [(CGFloat, CGFloat)] = small ? [(5, 6), (10, 12), (15, 6)] : [(5, 6), (8, 12), (11, 8), (14, 12), (17, 6)]
    let width: CGFloat = small ? 3 : 2
    for (x, h) in bars {
        ctx.fill(CGRect(x: x, y: 16 - h / 2, width: width, height: h))
    }
    ctx.setFillColor(orange)
    ctx.fill(CGRect(x: 21, y: 16, width: 6, height: 6))
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

// (file, points, scale)
let slots: [(String, Int, Int)] = [
    ("icon-16@1x.png", 16, 1), ("icon-16@2x.png", 16, 2), ("icon-32@1x.png", 32, 1), ("icon-32@2x.png", 32, 2),
    ("icon-128@1x.png", 128, 1), ("icon-128@2x.png", 128, 2), ("icon-256@1x.png", 256, 1), ("icon-256@2x.png", 256, 2),
    ("icon-512@1x.png", 512, 1), ("icon-512@2x.png", 512, 2),
]
for (file, points, scale) in slots {
    let data = render(pixels: points * scale, small: points <= 32)
    try! data.write(to: URL(fileURLWithPath: out).appendingPathComponent(file))
    print(file, points * scale, points <= 32 ? "3-bar" : "5-bar")
}
