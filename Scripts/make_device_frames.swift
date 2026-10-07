// Captioned App Store screenshots for iPad, Apple Vision Pro and Apple Watch, in the same design as
// the iPhone frames (make_store_frames.swift): void black, a violet glow, seeded stars, an amber eyebrow,
// a serif headline and the real capture as a floating screen. English only.
// Usage: swift Scripts/make_device_frames.swift  (run from the repo root)
// Reads Store/Screenshots/{iPad,Vision,Watch}; writes Store/Framed/iPad-13-inch (2064×2752),
// Store/Framed/Vision-Pro (3840×2160) and Store/Framed/Watch-Ultra (422×514), flattened, no alpha.
import AppKit

let amber = NSColor(srgbRed: 1, green: 0xB4/255, blue: 0x54/255, alpha: 1)
let signalRed = NSColor(srgbRed: 1, green: 0x45/255, blue: 0x3A/255, alpha: 1)
let starlight = NSColor(srgbRed: 0xF5/255, green: 0xF1/255, blue: 0xE6/255, alpha: 1)
let indigo = NSColor(srgbRed: 0x0B/255, green: 0x10/255, blue: 0x26/255, alpha: 1)
let violet = NSColor(srgbRed: 0x2A/255, green: 0x1B/255, blue: 0x4E/255, alpha: 1)
let rgb = CGColorSpaceCreateDeviceRGB()

struct Frame {
    let source: String
    let output: String
    let eyebrow: String
    let headline: String
    var subline: String? = nil   // under the headline
    var footnote: String? = nil  // under the screen: what the scene is, for computed skies
    var red = false
}

/// One canvas: its size and where the caption and screen sit, in pixels of that canvas.
struct Layout {
    let folder: String, source: String
    let width: CGFloat, height: CGFloat
    let eyebrowSize: CGFloat, eyebrowY: CGFloat, kern: CGFloat
    let headlineSize: CGFloat, headlineY: CGFloat, headlineHeight: CGFloat
    let sublineSize: CGFloat, sublineY: CGFloat
    let screenTop: CGFloat, screenTopWithSubline: CGFloat, screenBottom: CGFloat
    let corner: CGFloat, glow: CGFloat, stars: Int, starScale: CGFloat
    var footnoteSize: CGFloat = 0
}

func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
struct LCG { var s: UInt64; mutating func next() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(s >> 33) / CGFloat(1 << 31) } }

func render(_ frame: Frame, index: Int, _ L: Layout) -> Data? {
    let W = L.width, H = L.height
    guard let shot = NSImage(contentsOfFile: L.source + frame.source),
          let shotCG = shot.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let ctx = base.cgContext
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let accent = frame.red ? signalRed : amber

    ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let tint = frame.red ? signalRed.withAlphaComponent(0.22) : violet.withAlphaComponent(0.6)
    let glow = CGGradient(colorsSpace: rgb, colors: [tint.cgColor, indigo.withAlphaComponent(0.3).cgColor, NSColor.clear.cgColor] as CFArray, locations: [0, 0.45, 1])!
    let c = CGPoint(x: W / 2, y: H * 0.72)
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: max(W, H) * L.glow, options: [])
    var rng = LCG(s: UInt64(2003 + index * 37))
    for _ in 0..<L.stars {
        let x = rng.next() * W, y = rng.next() * H, r = (0.8 + rng.next() * 2.0) * L.starScale
        ctx.setFillColor((frame.red ? signalRed : starlight).withAlphaComponent(0.12 + rng.next() * 0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    let center = NSMutableParagraphStyle(); center.alignment = .center; center.lineSpacing = L.headlineSize * 0.06
    let margin = W * 0.04
    NSAttributedString(string: frame.eyebrow, attributes: [
        .font: NSFont.systemFont(ofSize: L.eyebrowSize, weight: .semibold), .foregroundColor: accent, .kern: L.kern, .paragraphStyle: center,
    ]).draw(in: CGRect(x: margin, y: L.eyebrowY, width: W - margin * 2, height: L.eyebrowSize * 1.6))
    NSAttributedString(string: frame.headline, attributes: [
        .font: serif(L.headlineSize), .foregroundColor: frame.red ? signalRed : starlight, .kern: -L.headlineSize * 0.006, .paragraphStyle: center,
    ]).draw(in: CGRect(x: margin, y: L.headlineY, width: W - margin * 2, height: L.headlineHeight))
    if let subline = frame.subline {
        NSAttributedString(string: subline, attributes: [
            .font: NSFont.systemFont(ofSize: L.sublineSize), .foregroundColor: starlight.withAlphaComponent(0.7), .paragraphStyle: center,
        ]).draw(in: CGRect(x: margin, y: L.sublineY, width: W - margin * 2, height: L.sublineSize * 1.6))
    }

    // The capture as a floating screen with an accent halo and a hairline edge.
    let top = frame.subline == nil ? L.screenTop : L.screenTopWithSubline
    let screenH = H - top - L.screenBottom
    let screenW = screenH * CGFloat(shotCG.width) / CGFloat(shotCG.height)
    let rect = CGRect(x: (W - screenW) / 2, y: top, width: screenW, height: screenH)
    let path = CGPath(roundedRect: rect, cornerWidth: L.corner, cornerHeight: L.corner, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: L.corner * 0.9, color: accent.withAlphaComponent(0.24).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(shotCG, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(starlight.withAlphaComponent(0.18).cgColor); ctx.setLineWidth(max(1, W / 700)); ctx.strokePath()

    if let footnote = frame.footnote, L.footnoteSize > 0 {
        NSAttributedString(string: footnote, attributes: [
            .font: NSFont.systemFont(ofSize: L.footnoteSize), .foregroundColor: starlight.withAlphaComponent(0.6), .paragraphStyle: center,
        ]).draw(in: CGRect(x: margin, y: rect.maxY + L.footnoteSize * 0.9, width: W - margin * 2, height: L.footnoteSize * 1.6))
    }

    NSGraphicsContext.current = nil
    // Flatten: App Store Connect rejects screenshots with an alpha channel.
    guard let cg = rep.cgImage,
          let flat = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let _ = Optional(flat.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))),
          let out = flat.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
}

// Captions: calm, short, no prices, no "new", no exclamation marks (as the iPhone set).
let iPad = (Layout(folder: "iPad-13-inch", source: "Store/Screenshots/iPad/", width: 2064, height: 2752,
                   eyebrowSize: 46, eyebrowY: 150, kern: 12,
                   headlineSize: 122, headlineY: 225, headlineHeight: 330,
                   sublineSize: 42, sublineY: 555,
                   screenTop: 640, screenTopWithSubline: 660, screenBottom: 110,
                   corner: 64, glow: 0.8, stars: 300, starScale: 1.5),
            [Frame(source: "01-tonight-13.png", output: "01-tonight.png", eyebrow: "TONIGHT", headline: "Where is the sky\ndarkest tonight?"),
             Frame(source: "02-detail-13.png", output: "02-score.png", eyebrow: "THE DARKNESS SCORE", headline: "One number,\nand its reasons."),
             Frame(source: "03-field-13.png", output: "03-field-mode.png", eyebrow: "FIELD MODE", headline: "Red light for\ndark-adapted eyes.", red: true),
             Frame(source: "04-calendar-13.png", output: "04-calendar.png", eyebrow: "BEST NIGHTS", headline: "Choose the night\nworth the drive."),
             Frame(source: "05-journal-13.png", output: "05-constellation.png", eyebrow: "YOUR CONSTELLATION", headline: "Every night\nbecomes a star.",
                   subline: "No account. No tracking. Your journal stays on this iPad."),
             Frame(source: "06-compass-13.png", output: "06-where-to-look.png", eyebrow: "WHERE TO LOOK", headline: "Hold up your iPad.\nFind the core.", red: true)])
let vision = (Layout(folder: "Vision-Pro", source: "Store/Screenshots/Vision/", width: 3840, height: 2160,
                     eyebrowSize: 50, eyebrowY: 105, kern: 14,
                     headlineSize: 108, headlineY: 172, headlineHeight: 280,
                     sublineSize: 0, sublineY: 0,
                     screenTop: 470, screenTopWithSubline: 470, screenBottom: 150,
                     corner: 72, glow: 0.7, stars: 420, starScale: 2.0, footnoteSize: 40),
              [Frame(source: "01-window.png", output: "01-window.png", eyebrow: "NYX ON APPLE VISION PRO", headline: "Plan the darkest night,\nright in your room."),
               Frame(source: "02-immersive-core.png", output: "02-immersive-core.png", eyebrow: "STAND UNDER TONIGHT'S SKY", headline: "The Milky Way,\nwhere it really is.",
                     footnote: "Joshua Tree tonight, computed on device."),
               Frame(source: "03-moonlit.png", output: "03-moonlit.png", eyebrow: "MOONLIGHT", headline: "See what a bright Moon\nwashes out.",
                     footnote: "Great Basin, July 15, 2027, computed on device."),
               Frame(source: "04-name-card.png", output: "04-name-card.png", eyebrow: "THE PLANETS", headline: "Look up.\nTap a planet for its name.",
                     footnote: "Joshua Tree before dawn: Jupiter above the rising crescent Moon.")])
let watch = (Layout(folder: "Watch-Ultra", source: "Store/Screenshots/Watch/", width: 422, height: 514,
                    eyebrowSize: 11, eyebrowY: 14, kern: 2.2,
                    headlineSize: 25, headlineY: 31, headlineHeight: 66,
                    sublineSize: 0, sublineY: 0,
                    screenTop: 104, screenTopWithSubline: 104, screenBottom: 12,
                    corner: 56, glow: 0.8, stars: 70, starScale: 0.45),
             [Frame(source: "01-tonight-ultra.png", output: "01-tonight.png", eyebrow: "TONIGHT", headline: "Tonight's sky,\non your wrist."),
              Frame(source: "02-milestones-ultra.png", output: "02-milestones.png", eyebrow: "THE NIGHT AHEAD", headline: "Every moment\nworth looking up."),
              Frame(source: "03-week-ultra.png", output: "03-week.png", eyebrow: "NEXT SEVEN NIGHTS", headline: "The darkest night\nthis week."),
              Frame(source: "04-parks-ultra.png", output: "04-parks.png", eyebrow: "SAVED PARKS", headline: "Your parks,\nfrom your iPhone."),
              Frame(source: "05-dark-adaptation-ultra.png", output: "05-dark-adaptation.png", eyebrow: "FIELD MODE", headline: "Red light for\ndark-adapted eyes.", red: true),
              Frame(source: "06-tonight-night-vision-ultra.png", output: "06-night-vision.png", eyebrow: "NIGHT VISION", headline: "The whole watch,\nin red light.", red: true)])

for (layout, frames) in [iPad, vision, watch] {
    let dir = URL(fileURLWithPath: "Store/Framed/" + layout.folder, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (i, frame) in frames.enumerated() {
        guard let png = render(frame, index: i, layout) else { print("failed \(frame.source)"); continue }
        try png.write(to: dir.appendingPathComponent(frame.output))
        print("wrote Store/Framed/\(layout.folder)/\(frame.output)")
    }
}
