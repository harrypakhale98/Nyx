// Nyx social promo: 1080×1920, 30 fps, H.264 + AAC. Real app footage, original score, motion type.
// swift promo.swift  (run in the folder above clips/, /tmp/nyx-promo by default: reads clips/*.mov, icon.png, nyx-score.m4a; writes nyx-promo.mp4)
import AVFoundation
import AppKit
import CoreImage

let format = CommandLine.arguments.dropFirst().first ?? "9x16"
let feed = format == "4x5"
let W = 1080.0, H = feed ? 1350.0 : 1920.0, fps = 30.0, total = 37.5
/// Where things sit. 9:16 keeps captions below the top 220 px and lets the phone run off the bottom,
/// the way Reels, TikTok and Shorts overlay their own controls; 4:5 is a feed post.
struct Layout { let eyebrowY, headlineTop, headlineSize, phoneTop, phoneH, introY, cardY: Double }
let layout = feed ? Layout(eyebrowY: 70, headlineTop: 104, headlineSize: 58, phoneTop: 268, phoneH: 1300, introY: 520, cardY: 330)
                  : Layout(eyebrowY: 238, headlineTop: 276, headlineSize: 68, phoneTop: 470, phoneH: 1580, introY: 760, cardY: 640)
let amber = NSColor(srgbRed: 1, green: 0xB4/255, blue: 0x54/255, alpha: 1)
let red = NSColor(srgbRed: 1, green: 0x45/255, blue: 0x3A/255, alpha: 1)
let starlight = NSColor(srgbRed: 0xF5/255, green: 0xF1/255, blue: 0xE6/255, alpha: 1)
let violet = NSColor(srgbRed: 0x2A/255, green: 0x1B/255, blue: 0x4E/255, alpha: 1)
let indigo = NSColor(srgbRed: 0x0B/255, green: 0x10/255, blue: 0x26/255, alpha: 1)

// MARK: easing
func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
func smooth(_ x: Double) -> Double { let t = clamp(x); return t * t * (3 - 2 * t) }
func easeOut(_ x: Double) -> Double { let t = clamp(x); return 1 - pow(1 - t, 3) }
func easeOutBack(_ x: Double) -> Double { let t = clamp(x), c = 1.4; return 1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2) }
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func mix(_ a: NSColor, _ b: NSColor, _ k: Double) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * k, green: a.greenComponent + (b.greenComponent - a.greenComponent) * k,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * k, alpha: 1)
}
func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

// MARK: footage
final class Clip {
    let reader: AVAssetReader, output: AVAssetReaderTrackOutput
    var current: CGImage?, nextSample: CMSampleBuffer?
    let ci = CIContext()
    init(_ path: String) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = asset.tracks(withMediaType: .video)[0]
        reader = try! AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); reader.startReading()
        nextSample = output.copyNextSampleBuffer()
    }
    /// The latest frame at or before clip time t (call with increasing t).
    func frame(at t: Double) -> CGImage? {
        while let s = nextSample, CMSampleBufferGetPresentationTimeStamp(s).seconds <= t {
            if let pb = CMSampleBufferGetImageBuffer(s) { current = ci.createCGImage(CIImage(cvPixelBuffer: pb), from: CIImage(cvPixelBuffer: pb).extent) }
            nextSample = output.copyNextSampleBuffer()
        }
        if current == nil, let s = nextSample, let pb = CMSampleBufferGetImageBuffer(s) { current = ci.createCGImage(CIImage(cvPixelBuffer: pb), from: CIImage(cvPixelBuffer: pb).extent) }
        return current
    }
}

struct Shot { let clip: String; let inPoint: Double; let start: Double; let end: Double; let eyebrow: String; let headline: String; let red: Bool }
let shots = [
    Shot(clip: "tonight", inPoint: 6.6, start: 3.4, end: 7.4, eyebrow: "TONIGHT", headline: "The darkest sky\nwithin your reach.", red: false),
    Shot(clip: "open", inPoint: 5.0, start: 7.4, end: 11.9, eyebrow: "THE DARKNESS SCORE", headline: "One number,\nand its reasons.", red: false),
    Shot(clip: "river", inPoint: 7.1, start: 11.9, end: 16.9, eyebrow: "THIRTY NIGHTS AHEAD", headline: "Scrub the month.\nWatch the Moon.", red: false),
    Shot(clip: "calendar", inPoint: 4.4, start: 16.9, end: 20.9, eyebrow: "BEST NIGHTS", headline: "Choose the night\nworth the drive.", red: false),
    Shot(clip: "journal", inPoint: 4.0, start: 20.9, end: 24.9, eyebrow: "YOUR CONSTELLATION", headline: "Every night you go\nbecomes a star.", red: false),
    Shot(clip: "field", inPoint: 4.0, start: 24.9, end: 28.9, eyebrow: "FIELD MODE", headline: "Red light for\ndark-adapted eyes.", red: true),
    Shot(clip: "compass", inPoint: 3.8, start: 28.9, end: 32.9, eyebrow: "WHERE TO LOOK", headline: "Point your iPhone.\nFind the Milky Way.", red: true),
]
let fade = 0.35
var clips: [String: Clip] = [:]
for s in shots { clips[s.clip] = Clip("clips/\(s.clip).mov") }
let icon = NSImage(contentsOfFile: "icon.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!

// MARK: stars (seeded, three depths)
struct Star { var x, y, r, a, phase, speed, depth: Double }
var seed: UInt64 = 2026
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
let stars: [Star] = (0..<340).map { _ in
    let depth = [0.35, 0.65, 1.0][Int(rnd() * 3)]
    return Star(x: rnd() * W, y: rnd() * H, r: (0.7 + rnd() * 1.8) * depth + 0.3, a: 0.15 + rnd() * 0.6 * depth, phase: rnd() * 6.28, speed: 0.6 + rnd() * 1.6, depth: depth)
}

// MARK: drawing helpers
func text(_ s: String, font: NSFont, color: NSColor, kern: CGFloat = 0, center: CGPoint, alpha: Double, lineSpacing: CGFloat = 0) {
    guard alpha > 0.001 else { return }
    let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineSpacing = lineSpacing
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha), .kern: kern, .paragraphStyle: p])
    let size = str.boundingRect(with: CGSize(width: W - 120, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
    str.draw(with: CGRect(x: 60, y: center.y - size.height / 2, width: W - 120, height: size.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
}
func headline(_ s: String, color: NSColor, accentWord: String? = nil, accent: NSColor = amber, top: CGFloat, size: CGFloat, t: Double, delay: Double, out: Double) {
    // Each line rises and fades in on its own beat.
    for (i, line) in s.split(separator: "\n").enumerated() {
        let k = easeOut(ramp(t, delay + Double(i) * 0.14, delay + Double(i) * 0.14 + 0.7))
        let alpha = k * (1 - smooth(ramp(t, out, out + 0.3)))
        guard alpha > 0.001 else { continue }
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let str = NSMutableAttributedString(string: String(line), attributes: [.font: serif(size), .foregroundColor: color.withAlphaComponent(alpha), .kern: -size * 0.01, .paragraphStyle: p])
        if let w = accentWord, let r = line.range(of: w) { str.addAttribute(.foregroundColor, value: accent.withAlphaComponent(alpha), range: NSRange(r, in: line)) }
        let y = top + CGFloat(i) * size * 1.16 + CGFloat((1 - k) * 26)
        str.draw(with: CGRect(x: 40, y: y, width: W - 80, height: size * 1.4), options: [.usesLineFragmentOrigin])
    }
}

func render(_ t: Double, into ctx: CGContext) {
    // Flipped: top-left origin, y down.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let rgb = CGColorSpaceCreateDeviceRGB()

    // How red the night is: field mode and the compass.
    let redK = smooth(ramp(t, 24.6, 25.2)) * (1 - smooth(ramp(t, 32.7, 33.4)))
    let accent = mix(amber, red, redK)

    // Background: void black, a breathing glow behind the phone, drifting stars, vignette.
    ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let breath = 0.85 + 0.15 * sin(t * 0.9)
    let glowColor = mix(violet, NSColor(srgbRed: 0.35, green: 0.05, blue: 0.04, alpha: 1), redK)
    let glow = CGGradient(colorsSpace: rgb, colors: [glowColor.withAlphaComponent(0.85 * breath).cgColor, indigo.withAlphaComponent(0.35).cgColor, NSColor.clear.cgColor] as CFArray, locations: [0, 0.45, 1])!
    let gc = CGPoint(x: W / 2, y: H * (feed ? 0.58 : 0.62))
    ctx.drawRadialGradient(glow, startCenter: gc, startRadius: 0, endCenter: gc, endRadius: W * 1.15, options: [])
    for s in stars {
        var x = (s.x - t * 6 * s.depth).truncatingRemainder(dividingBy: W); if x < 0 { x += W }
        var y = (s.y - t * 10 * s.depth).truncatingRemainder(dividingBy: H); if y < 0 { y += H }
        let tw = 0.55 + 0.45 * sin(t * s.speed * 2 + s.phase)
        let c = mix(starlight, red, redK * 0.85)
        ctx.setFillColor(c.withAlphaComponent(s.a * tw).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - s.r, y: y - s.r, width: s.r * 2, height: s.r * 2))
    }
    // Shooting stars: one in the opening, one over the final card.
    for (t0, x0, y0) in [(1.55, 860.0, feed ? 160.0 : 300.0), (34.15, 900.0, feed ? 120.0 : 420.0)] where t >= t0 && t <= t0 + 0.9 {
        let k = (t - t0) / 0.9
        let head = CGPoint(x: x0 - easeOut(k) * 620, y: y0 + easeOut(k) * 330)
        let tail = CGPoint(x: head.x + 230, y: head.y - 122)
        let a = sin(k * .pi)
        let g = CGGradient(colorsSpace: rgb, colors: [starlight.withAlphaComponent(0.95 * a).cgColor, starlight.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.setLineWidth(3); ctx.setLineCap(.round)
        ctx.move(to: head); ctx.addLine(to: tail); ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.drawLinearGradient(g, start: head, end: tail, options: [])
        ctx.restoreGState()
        ctx.setFillColor(starlight.withAlphaComponent(a).cgColor); ctx.fillEllipse(in: CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6))
    }

    // MARK: opening
    if t < 3.6 {
        let out = 2.95
        text("63 NATIONAL PARKS", font: .systemFont(ofSize: 30, weight: .semibold), color: amber, kern: 9, center: CGPoint(x: W / 2, y: layout.introY),
             alpha: easeOut(ramp(t, 0.35, 0.95)) * (1 - smooth(ramp(t, out, out + 0.35))))
        headline("Which sky is\ndarkest tonight?", color: starlight, accentWord: "darkest", top: layout.introY + 55, size: feed ? 88 : 96, t: t, delay: 0.9, out: out)
    }

    // MARK: the phone and its captions
    let phoneIn = easeOutBack(ramp(t, 3.15, 4.05))
    let phoneOut = smooth(ramp(t, 32.8, 33.5))
    if t >= 3.15 && phoneOut < 1 {
        let ph = layout.phoneH, pw = ph * 1206 / 2622
        let scale = 1 - 0.08 * phoneOut
        let float = sin(t * 0.8) * 5
        let cx = W / 2, cy = layout.phoneTop + ph / 2 + (1 - phoneIn) * 160 + float + phoneOut * 40
        let screen = CGRect(x: cx - pw * scale / 2, y: cy - ph * scale / 2, width: pw * scale, height: ph * scale)
        let alpha = min(1, ramp(t, 3.15, 3.7)) * (1 - phoneOut)
        let radius = pw * scale * 0.135
        ctx.saveGState()
        ctx.setAlpha(alpha)
        // Device body: a thin dark-titanium band with a hairline highlight, and the accent halo.
        let body = screen.insetBy(dx: -15 * scale, dy: -15 * scale)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: radius + 15 * scale, cornerHeight: radius + 15 * scale, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 110, color: accent.withAlphaComponent(0.30).cgColor)
        ctx.addPath(bodyPath); ctx.setFillColor(NSColor(srgbRed: 0.07, green: 0.07, blue: 0.085, alpha: 1).cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(bodyPath); ctx.setStrokeColor(starlight.withAlphaComponent(0.22).cgColor); ctx.setLineWidth(2); ctx.strokePath()
        let screenPath = CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(screenPath); ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(screen)
        ctx.interpolationQuality = .high
        // Footage: each shot crossfades into the next.
        for (i, s) in shots.enumerated() {
            let from = s.start - (i == 0 ? 0.25 : fade), to = s.end + (i == shots.count - 1 ? 1.0 : 0)
            guard t >= from && t < to else { continue }
            let a = i == 0 ? 1 : smooth(ramp(t, s.start - fade, s.start))
            guard let img = clips[s.clip]?.frame(at: s.inPoint + (t - s.start)) else { continue }
            ctx.saveGState(); ctx.setAlpha(a)
            ctx.translateBy(x: screen.minX, y: screen.maxY); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: screen.size))
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Captions above the phone.
        for s in shots where t >= s.start - 0.05 && t < s.end + 0.05 {
            let lt = t - s.start, dur = s.end - s.start
            let c = s.red ? red : starlight
            text(s.eyebrow, font: .systemFont(ofSize: feed ? 27 : 30, weight: .semibold), color: s.red ? red : amber, kern: 8, center: CGPoint(x: W / 2, y: layout.eyebrowY),
                 alpha: easeOut(ramp(lt, 0.05, 0.45)) * (1 - smooth(ramp(lt, dur - 0.32, dur))))
            headline(s.headline, color: c, top: layout.headlineTop, size: layout.headlineSize, t: lt, delay: 0.12, out: dur - 0.32)
        }
    }

    // MARK: final card
    if t >= 33.1 {
        let lt = t - 33.1
        let k = easeOutBack(ramp(lt, 0.15, 1.0)), a = smooth(ramp(lt, 0.15, 0.6))
        let size = 300.0 * (0.82 + 0.18 * k)
        let y0 = layout.cardY
        let rect = CGRect(x: W / 2 - size / 2, y: y0 - size / 2, width: size, height: size)
        ctx.saveGState()
        ctx.setAlpha(a)
        ctx.setShadow(offset: .zero, blur: 90, color: amber.withAlphaComponent(0.35).cgColor)
        ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(icon, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
        headline("Nyx", color: starlight, top: y0 + 190, size: 150, t: lt, delay: 0.55, out: 99)
        text("DARK SKY PLANNER", font: .systemFont(ofSize: 32, weight: .medium), color: starlight.withAlphaComponent(0.75), kern: 12, center: CGPoint(x: W / 2, y: y0 + 412), alpha: easeOut(ramp(lt, 0.85, 1.4)))
        text("63 national parks. Every night, scored.", font: serif(44), color: starlight.withAlphaComponent(0.92), center: CGPoint(x: W / 2, y: y0 + 530), alpha: easeOut(ramp(lt, 1.15, 1.7)))
        text("Free on the App Store", font: .systemFont(ofSize: 46, weight: .semibold), color: amber, center: CGPoint(x: W / 2, y: y0 + 690), alpha: easeOut(ramp(lt, 1.5, 2.0)))
        text("No account. No ads. No tracking.", font: .systemFont(ofSize: 32), color: starlight.withAlphaComponent(0.6), center: CGPoint(x: W / 2, y: y0 + 760), alpha: easeOut(ramp(lt, 1.8, 2.3)))
    }

    // Vignette and the closing fade.
    let vig = CGGradient(colorsSpace: rgb, colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor] as CFArray, locations: [0.55, 1])!
    ctx.drawRadialGradient(vig, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: H * 0.62, options: [.drawsAfterEndLocation])
    let close = smooth(ramp(t, total - 0.45, total)), open = 1 - smooth(ramp(t, 0, 0.5))
    if close + open > 0 { ctx.setFillColor(NSColor.black.withAlphaComponent(max(close, open)).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }

    NSGraphicsContext.current = nil
    ctx.restoreGState()
}

// MARK: write video, then add the score
let videoURL = URL(fileURLWithPath: "promo-video-\(format).mov"), finalURL = URL(fileURLWithPath: "nyx-promo-\(format).mp4")
try? FileManager.default.removeItem(at: videoURL); try? FileManager.default.removeItem(at: finalURL)
let writer = try! AVAssetWriter(outputURL: videoURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 30],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H)])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
let frames = Int(total * fps)
for f in 0..<frames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!),
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    render(Double(f) / fps, into: ctx)
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
    if f % 150 == 0 { print("frame \(f)/\(frames)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }; done.wait()

let comp = AVMutableComposition()
let vAsset = AVURLAsset(url: videoURL), aAsset = AVURLAsset(url: URL(fileURLWithPath: "nyx-score.m4a"))
let range = CMTimeRange(start: .zero, duration: CMTime(seconds: total, preferredTimescale: 600))
try! comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: vAsset.tracks(withMediaType: .video)[0], at: .zero)
try! comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: aAsset.tracks(withMediaType: .audio)[0], at: .zero)
let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
export.outputURL = finalURL; export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
export.exportAsynchronously { done.signal() }; done.wait()
do {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    for c in clips.values { _ = c }  // footage is not on the card
    render(36.4, into: ctx)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "nyx-promo-cover-\(format).png"))
}
print("export", export.status == .completed ? "completed" : "failed \(String(describing: export.error))", finalURL.path)
