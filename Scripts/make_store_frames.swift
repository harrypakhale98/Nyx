// Builds captioned App Store screenshots from the raw captures in Store/Screenshots.
// Usage: swift Scripts/make_store_frames.swift  (run from the repo root)
// Writes Store/Framed/6.9-inch (1320×2868) and Store/Framed/6.5-inch (1284×2778), flattened, no alpha.
import AppKit

struct Frame {
    let source: String
    let output: String
    let eyebrow: String
    let headline: String
    var subline: String? = nil
    var accent = NSColor(srgbRed: 1, green: 0xB4/255, blue: 0x54/255, alpha: 1)
}

let signalRed = NSColor(srgbRed: 1, green: 0x45/255, blue: 0x3A/255, alpha: 1)
let frames = [
    Frame(source: "01-tonight-6.9.png", output: "01-tonight.png",
          eyebrow: "TONIGHT", headline: "Where is the sky\ndarkest tonight?"),
    Frame(source: "02-detail-6.9.png", output: "02-score.png",
          eyebrow: "THE DARKNESS SCORE", headline: "Moon, clouds, light pollution.\nOne honest number."),
    Frame(source: "03-calendar-6.9.png", output: "03-calendar.png",
          eyebrow: "BEST NIGHTS", headline: "Choose the night\nworth the drive."),
    Frame(source: "04-parks-6.9.png", output: "04-parks.png",
          eyebrow: "63 NATIONAL PARKS", headline: "Every park,\nand its best night this week."),
    Frame(source: "06-learn-6.9.png", output: "05-night-vision.png",
          eyebrow: "NIGHT VISION", headline: "Red light that keeps\nyour eyes dark-adapted.", accent: signalRed),
    Frame(source: "05-journal-6.9.png", output: "06-journal.png",
          eyebrow: "JOURNAL", headline: "Keep a little\nof the night.",
          subline: "No account. No tracking. Your journal stays on this iPhone."),
]

let starlight = NSColor(srgbRed: 0xF5/255, green: 0xF1/255, blue: 0xE6/255, alpha: 1)
let indigo = NSColor(srgbRed: 0x0B/255, green: 0x10/255, blue: 0x26/255, alpha: 1)
let violet = NSColor(srgbRed: 0x2A/255, green: 0x1B/255, blue: 0x4E/255, alpha: 1)
let rgb = CGColorSpaceCreateDeviceRGB()

func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

// Deterministic generator so every run draws the same stars.
struct LCG { var s: UInt64; mutating func next() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(s >> 33) / CGFloat(1 << 31) } }

func render(_ frame: Frame, index: Int, width W: CGFloat, height H: CGFloat) -> Data? {
    guard let shot = NSImage(contentsOfFile: "Store/Screenshots/" + frame.source),
          let shotCG = shot.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let u = H / 2868  // layout unit, so both sizes share one design
    let ctx = base.cgContext
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)  // top-left origin
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Void black with a low violet/indigo glow behind the phone.
    ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let glowTint = frame.accent == signalRed ? signalRed.withAlphaComponent(0.22) : violet.withAlphaComponent(0.6)
    let glow = CGGradient(colorsSpace: rgb, colors: [glowTint.cgColor, indigo.withAlphaComponent(0.3).cgColor, NSColor.clear.cgColor] as CFArray,
                          locations: [0, 0.45, 1])!
    let glowCenter = CGPoint(x: W / 2, y: H * 0.78)
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: W * 0.95, options: [])

    var rng = LCG(s: UInt64(1009 + index * 31))
    for _ in 0..<260 {
        let x = rng.next() * W, y = rng.next() * H, r = (0.8 + rng.next() * 2.0) * u
        let a = 0.12 + rng.next() * 0.55
        ctx.setFillColor((frame.accent == signalRed ? signalRed : starlight).withAlphaComponent(a).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Eyebrow, headline and optional subline.
    let center = NSMutableParagraphStyle(); center.alignment = .center; center.lineSpacing = 6 * u
    NSAttributedString(string: frame.eyebrow, attributes: [
        .font: NSFont.systemFont(ofSize: 34 * u, weight: .semibold), .foregroundColor: frame.accent,
        .kern: 9.0 * u, .paragraphStyle: center,
    ]).draw(in: CGRect(x: 60 * u, y: 190 * u, width: W - 120 * u, height: 50 * u))
    let longest = frame.headline.split(separator: "\n").map(\.count).max() ?? 0
    let headSize: CGFloat = (longest > 24 ? 84 : 100) * u
    NSAttributedString(string: frame.headline, attributes: [
        .font: serif(headSize), .foregroundColor: frame.accent == signalRed ? signalRed : starlight,
        .kern: -0.6 * u, .paragraphStyle: center,
    ]).draw(in: CGRect(x: 50 * u, y: 262 * u, width: W - 100 * u, height: 280 * u))
    if let subline = frame.subline {
        NSAttributedString(string: subline, attributes: [
            .font: NSFont.systemFont(ofSize: 32 * u), .foregroundColor: starlight.withAlphaComponent(0.7), .paragraphStyle: center,
        ]).draw(in: CGRect(x: 60 * u, y: 548 * u, width: W - 120 * u, height: 50 * u))
    }

    // The full capture as a floating screen with an accent halo and hairline edge.
    let phoneH = 2150 * u
    let phoneW = phoneH * CGFloat(shotCG.width) / CGFloat(shotCG.height)
    let rect = CGRect(x: (W - phoneW) / 2, y: (frame.subline == nil ? 640 : 660) * u, width: phoneW, height: phoneH)
    let path = CGPath(roundedRect: rect, cornerWidth: 118 * u, cornerHeight: 118 * u, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 90 * u, color: frame.accent.withAlphaComponent(0.22).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(shotCG, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(starlight.withAlphaComponent(0.18).cgColor); ctx.setLineWidth(3 * u); ctx.strokePath()

    NSGraphicsContext.current = nil
    // Flatten: App Store Connect rejects screenshots with an alpha channel.
    guard let cg = rep.cgImage,
          let flat = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    flat.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    guard let out = flat.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
}

for (folder, w, h) in [("6.9-inch", 1320.0, 2868.0), ("6.5-inch", 1284.0, 2778.0)] {
    let dir = URL(fileURLWithPath: "Store/Framed/\(folder)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (i, frame) in frames.enumerated() {
        guard let png = render(frame, index: i, width: CGFloat(w), height: CGFloat(h)) else { print("failed \(frame.source)"); continue }
        try png.write(to: dir.appendingPathComponent(frame.output))
        print("wrote Store/Framed/\(folder)/\(frame.output)")
    }
}
