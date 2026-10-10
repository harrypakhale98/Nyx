// Builds 1080×1350 (4:5) social images from the App Store screenshots.
// Usage: swift Scripts/make_social.swift  (run from the repo root)
// The sources are the 1.2 App Store frames in `Store/1.2 v10/iPhone/6.3-inch` (1206×2622), which already carry
// their eyebrow, caption and starfield (`Scripts/make_store_frames.swift`). A framed source is drawn
// whole across the card's width from the top, cut at 4:5 with the bottom fading into the night, so
// its caption is the card's headline. A raw capture (`framed: false`) gets this script's own eyebrow,
// headline and rounded phone, as before.
import AppKit

struct Card {
    let source: String
    let output: String
    let eyebrow: String
    let headline: String
    let cropTop: CGFloat  // fraction of the capture hidden above the frame
    var framed = false    // an App Store frame that already carries its own caption
    var scale: CGFloat = 1  // framed only: the frame's width as a share of the card's, so more of its screen fits
}

// Framed sources: the eyebrow and headline below are the frames' own captions, for reference.
let cards = [
    Card(source: "Store/1.2 v10/iPhone/6.3-inch/01-tonights-sky.png", output: "01-sky.png",
         eyebrow: "TONIGHT'S SKY", headline: "The night sky,\nbefore you go.", cropTop: 0, framed: true),
    Card(source: "Store/1.2 v10/iPhone/6.3-inch/02-tonight.png", output: "02-tonight.png",
         eyebrow: "TONIGHT", headline: "Where is the sky\ndarkest tonight?", cropTop: 0, framed: true,
         scale: 0.9),  // the whole dial and its band word
    Card(source: "Store/1.2 v10/iPhone/6.3-inch/07-calendar.png", output: "03-calendar.png",
         eyebrow: "BEST NIGHTS", headline: "Choose the night\nworth the drive.", cropTop: 0, framed: true,
         scale: 0.72),  // the month's nights, not only its header
    Card(source: "Store/1.2 v10/iPhone/6.3-inch/08-city-light.png", output: "04-city-light.png",
         eyebrow: "WHAT CITY LIGHT TAKES", headline: "See the stars\na city would hide.", cropTop: 0, framed: true,
         scale: 0.8),  // smaller, so the Here / City switch and "An illustration" stay on the card
]

let W: CGFloat = 1080, H: CGFloat = 1350
let starlight = NSColor(srgbRed: 0xF5/255, green: 0xF1/255, blue: 0xE6/255, alpha: 1)
let amber = NSColor(srgbRed: 1, green: 0xB4/255, blue: 0x54/255, alpha: 1)
let indigo = NSColor(srgbRed: 0x0B/255, green: 0x10/255, blue: 0x26/255, alpha: 1)
let violet = NSColor(srgbRed: 0x2A/255, green: 0x1B/255, blue: 0x4E/255, alpha: 1)

func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return NSFont(name: "New York", size: size) ?? base
}

// Small deterministic generator so every run draws the same stars.
struct LCG { var s: UInt64; mutating func next() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(s >> 33) / CGFloat(1 << 31) } }

let outDir = URL(fileURLWithPath: "Store/Social", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (index, card) in cards.enumerated() {
    guard let shot = NSImage(contentsOfFile: card.source),
          let shotCG = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("missing \(card.source)"); continue
    }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    // Flip to top-left origin.
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)

    if card.framed {
        // The store frame across the full width, top-aligned: its caption and the top of its screen.
        let width = W * card.scale, left = (W - width) / 2
        let height = CGFloat(shotCG.height) * width / CGFloat(shotCG.width)
        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        if card.scale < 1 {
            // Stars in the margins beside a smaller frame, so its edges never read as a box.
            var rng = LCG(s: UInt64(42 + index * 7))
            for _ in 0..<120 {
                let x = rng.next() * W, y = rng.next() * H, r = 0.6 + rng.next() * 1.4
                guard x < left || x > left + width else { continue }
                ctx.setFillColor(starlight.withAlphaComponent(0.12 + rng.next() * 0.45).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.saveGState()
        ctx.translateBy(x: left, y: height); ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(shotCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.restoreGState()
    } else {

    // Void black, with a low indigo/violet glow behind the phone.
    ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [violet.withAlphaComponent(0.55).cgColor, indigo.withAlphaComponent(0.35).cgColor, NSColor.clear.cgColor] as CFArray,
                          locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W/2, y: H * 0.95), startRadius: 0,
                           endCenter: CGPoint(x: W/2, y: H * 0.95), endRadius: W * 0.85, options: [])

    // Seeded starfield.
    var rng = LCG(s: UInt64(42 + index * 7))
    for _ in 0..<170 {
        let x = rng.next() * W, y = rng.next() * H
        let r = 0.6 + rng.next() * 1.6
        ctx.setFillColor(starlight.withAlphaComponent(0.15 + rng.next() * 0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Eyebrow and headline. NSString drawing expects a flipped context.
    let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = flipped
    let eyebrowAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: amber, .kern: 6.0]
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 4
    let eyebrow = NSAttributedString(string: card.eyebrow, attributes: eyebrowAttrs.merging([.paragraphStyle: para]) { $1 })
    eyebrow.draw(in: CGRect(x: 60, y: 84, width: W - 120, height: 34))
    let headSize: CGFloat = card.headline.count > 40 ? 56 : 68
    let head = NSAttributedString(string: card.headline, attributes: [
        .font: serif(headSize), .foregroundColor: starlight, .paragraphStyle: para, .kern: -0.5])
    head.draw(in: CGRect(x: 50, y: 132, width: W - 100, height: 200))

    // Phone capture, rounded, bleeding off the bottom edge.
    let phoneW: CGFloat = 640
    let scale = phoneW / CGFloat(shotCG.width)
    let phoneH = CGFloat(shotCG.height) * scale
    let top: CGFloat = 350
    let frame = CGRect(x: (W - phoneW) / 2, y: top - card.cropTop * phoneH, width: phoneW, height: phoneH)
    let visible = CGRect(x: frame.minX, y: top, width: phoneW, height: H - top + 80)
    let radius: CGFloat = 78
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: amber.withAlphaComponent(0.18).cgColor)
    let path = CGPath(roundedRect: card.cropTop == 0 ? frame : visible, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    // Draw the image upright inside the flipped context.
    ctx.saveGState()
    ctx.translateBy(x: frame.minX, y: frame.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(shotCG, in: CGRect(x: 0, y: 0, width: phoneW, height: phoneH))
    ctx.restoreGState()
    if card.cropTop > 0 {
        // Soft fade where the capture is cut, so it reads as a scroll, not a crop.
        let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: top + 90), options: [])
    }
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(starlight.withAlphaComponent(0.16).cgColor); ctx.setLineWidth(2); ctx.strokePath()
    }

    // Fade the bottom edge into the night.
    let bottom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bottom, start: CGPoint(x: 0, y: H - 170), end: CGPoint(x: 0, y: H), options: [])

    NSGraphicsContext.current = nil
    // Flatten (no alpha) for upload.
    guard let cg = rep.cgImage,
          let flat = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    flat.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    guard let out = flat.makeImage(),
          let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { continue }
    try png.write(to: outDir.appendingPathComponent(card.output))
    print("wrote Store/Social/\(card.output)")
}
