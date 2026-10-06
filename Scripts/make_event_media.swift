// Composes the In-App Event media (Store/1.1/in-app-events.md) from the raw captures of
// Scripts/capture_events.py. Usage: swift Scripts/make_event_media.swift [raw folder]  (from the repo root)
// Writes Store/1.1/events/<slug>-16x9.png (event card, 1920×1080) and <slug>-9x16.png (details page,
// 1080×1920): the park's computed sky for that night, edge to edge, with the real iPhone screen for the
// same park and night floating on it. Flattened sRGB PNG, no alpha.
// No text and no logos are added: Apple's in-app event guidance asks for media without text, since the
// App Store sets the event name, badge and description over it, adds its own gradient, crops about 75 px
// from each side of the card and blurs the lower part of the details image. Key content therefore sits
// in the upper, central part of each picture, and no border or gradient is drawn at the edges.
import AppKit
import ImageIO

let raw = CommandLine.arguments.dropFirst().first ?? "/tmp/NyxEventRaw"
let output = URL(fileURLWithPath: "Store/1.1/events", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let starlight = CGColor(srgbRed: 0xF5/255, green: 0xF1/255, blue: 0xE6/255, alpha: 1)
let amber = CGColor(srgbRed: 1, green: 0xB4/255, blue: 0x54/255, alpha: 1)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Loads a capture upright: the UI test runner's landscape iPad screenshots carry an orientation.
func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                    kCGImageSourceCreateThumbnailWithTransform: true,
                                    kCGImageSourceThumbnailMaxPixelSize: 4000]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

/// Fills `canvas` with the part of `sky` inside `crop` (pixels, top-left origin).
func drawSky(_ sky: CGImage, crop: CGRect, in ctx: CGContext, canvas: CGSize) {
    guard let part = sky.cropping(to: crop.integral) else { return }
    ctx.interpolationQuality = .high
    ctx.draw(part, in: CGRect(origin: .zero, size: canvas))
}

/// The iPhone screen as a floating pane: soft moon-amber halo, rounded corners, hairline edge.
/// `rect` is in top-left coordinates; the context is bottom-left, so it is flipped here.
func drawPhone(_ shot: CGImage, rect r: CGRect, canvasHeight H: CGFloat, in ctx: CGContext) {
    let rect = CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height)
    let radius = r.width * 0.118
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: r.width * 0.12, color: amber.copy(alpha: 0.2))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: rect)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(starlight.copy(alpha: 0.2)!); ctx.setLineWidth(max(1.5, r.width * 0.003)); ctx.strokePath()
}

func write(_ ctx: CGContext, to url: URL) throws {
    guard let image = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
    try png.write(to: url)
    print("wrote \(url.path)")
}

func canvas(_ w: Int, _ h: Int) -> CGContext? {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    ctx?.setFillColor(CGColor(gray: 0, alpha: 1)); ctx?.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx
}

let skies = (try FileManager.default.contentsOfDirectory(atPath: raw)).filter { $0.hasSuffix("-sky.png") }.sorted()
for name in skies {
    let slug = String(name.dropLast("-sky.png".count))
    guard let sky = load("\(raw)/\(name)"), let card = load("\(raw)/\(slug)-card.png"), let details = load("\(raw)/\(slug)-details.png") else {
        print("missing captures for \(slug)"); continue
    }
    let sw = CGFloat(sky.width), sh = CGFloat(sky.height)  // landscape iPad, 2752×2064
    let phoneAspect = CGFloat(card.width) / CGFloat(card.height)

    // Event card, 16:9: the middle band of the sky (status bar and home indicator fall outside it),
    // the phone right of centre, rising from the lower edge so its top half (the event's own line) is clear.
    if let ctx = canvas(1920, 1080) {
        let bandH = sw * 9 / 16
        drawSky(sky, crop: CGRect(x: 0, y: (sh - bandH) / 2, width: sw, height: bandH), in: ctx, canvas: CGSize(width: 1920, height: 1080))
        let phoneW: CGFloat = 640, phoneH = phoneW / phoneAspect
        drawPhone(card, rect: CGRect(x: 1920 * 0.64 - phoneW / 2, y: 92, width: phoneW, height: phoneH), canvasHeight: 1080, in: ctx)
        try write(ctx, to: output.appendingPathComponent("\(slug)-16x9.png"))
    }
    // Details page, 9:16: a tall slice from the middle of the same sky below the status bar, the phone
    // centred in the upper part; the lowest ~500 px, which the App Store blurs under its text, hold only sky.
    if let ctx = canvas(1080, 1920) {
        let top: CGFloat = 96, cropH = sh - top - 48, cropW = cropH * 9 / 16
        drawSky(sky, crop: CGRect(x: (sw - cropW) / 2, y: top, width: cropW, height: cropH), in: ctx, canvas: CGSize(width: 1080, height: 1920))
        let phoneH: CGFloat = 1480, phoneW = phoneH * phoneAspect
        drawPhone(details, rect: CGRect(x: (1080 - phoneW) / 2, y: 120, width: phoneW, height: phoneH), canvasHeight: 1920, in: ctx)
        try write(ctx, to: output.appendingPathComponent("\(slug)-9x16.png"))
    }
}
