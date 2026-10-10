#if DEBUG
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// `-nyx-export-promo sky|moon|all` (with `-nyx-screen detail -nyx-park deva -nyx-date 2027-07-03`):
/// frame sequences for the promotional film, drawn by the app's own renderers with no header,
/// controls or status bar, written as numbered PNGs (no alpha) under the app's Documents folder in
/// `promo/<name>/0000.png…`. Writes only local files; `promo/progress.txt` says how far it got.
///
/// - `sky-land` (2560 × 1440) and `sky-port` (1440 × 2560, with `-nyx-promo-portrait`): the same
///   `PanoramaCanvas` as the full-screen "Tonight's sky", as a time-lapse through the night.
///   `HorizonSkies` keeps one sky per park and five-minute slot, which would make a time-lapse
///   step; so each frame takes its own slot and shifts the park's longitude by the sidereal
///   difference, which puts every star where it stands at the frame's own instant. The Sun, the
///   planets and the Moon then sit where they were in that slot (at most about 15 hours away):
///   a fraction of a degree for the planets, the Sun's altitude within about half a degree,
///   and the Moon is left out (`showsMoon` off). Tuning: `-nyx-promo-start 60` (minutes after
///   true darkness begins), `-nyx-promo-minutes 210` (the span), `-nyx-promo-frames 360`,
///   `-nyx-promo-facing 180`, `-nyx-promo-altitude 24`, `-nyx-promo-span 1.35`,
///   `-nyx-promo-scale 2`, `-nyx-promo-labels 0` (no names or figures).
/// - `moon` (1600 × 1600): `MoonView` at large size (the atlas and LOLA relief), lunar north up,
///   through one lunation from a thin waxing crescent to a thin waning crescent, each frame the
///   Moon's real phase and libration at that instant (seen from the park). Tuning:
///   `-nyx-promo-moon-frames 300`, `-nyx-promo-moon-from 0.03` (the thinnest crescent lit).
@MainActor enum DebugPromoExport {
    static func runIfRequested(_ model:PlanModel) {
        guard let what=DebugScenario.text("-nyx-export-promo"), let park=model.home,
              let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first?.appendingPathComponent("promo") else { return }
        let night=model.night(park)
        Task {
            // After the first frames, so the page underneath has settled.
            try? await Task.sleep(for:.seconds(2))
            log(root,"start \(what) \(park.id) \(night.id)")
            if what=="sky" || what=="all" {
                await sky(park:park,night:night,folder:root.appendingPathComponent("sky-land"),pixels:CGSize(width:2560,height:1440),root:root)
                if DebugScenario.isEnabled("promo-portrait") {
                    await sky(park:park,night:night,folder:root.appendingPathComponent("sky-port"),pixels:CGSize(width:1440,height:2560),root:root)
                }
            }
            if what=="moon" || what=="all" { await moon(park:park,night:night,folder:root.appendingPathComponent("moon"),root:root) }
            log(root,"done")
        }
    }

    // MARK: The sky

    private static func sky(park:Park,night:Night,folder:URL,pixels:CGSize,root:URL) async {
        let frames=Int(DebugScenario.number("-nyx-promo-frames") ?? 360)
        let begin=night.sky.darkStart ?? SkyAlmanac.nightWindow(night.sky).start
        let start=begin.addingTimeInterval((DebugScenario.number("-nyx-promo-start") ?? 60)*60)
        let span=(DebugScenario.number("-nyx-promo-minutes") ?? 210)*60
        var options=PanoramaOptions(facing:DebugScenario.number("-nyx-promo-facing") ?? 180,
                                    centreAltitude:DebugScenario.number("-nyx-promo-altitude") ?? 24,
                                    span:DebugScenario.number("-nyx-promo-span") ?? 1.35,
                                    bortle:Double(park.bortleEstimate))
        options.showsMoon=false
        options.labels=DebugScenario.number("-nyx-promo-labels") != 0
        let scale=DebugScenario.number("-nyx-promo-scale") ?? 2
        let points=CGSize(width:pixels.width/scale,height:pixels.height/scale)
        guard let encoded=try? JSONEncoder().encode(park),
              let fields=(try? JSONSerialization.jsonObject(with:encoded)) as? [String:Any] else { return }
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let base=(start.timeIntervalSince1970/300).rounded(.down)*300
        let clock=Date.now
        for index in 0..<frames {
            let instant=start.addingTimeInterval(frames>1 ? span*Double(index)/Double(frames-1) : 0)
            // Its own five-minute slot, centred on the night, and the longitude that puts the stars
            // in that slot where they stand at `instant` (1.00273791 sidereal days per solar day).
            let slot=Date(timeIntervalSince1970:base+Double(index-frames/2)*300)
            let shift=360.98564736629*instant.timeIntervalSince(slot)/86_400
            var moved=fields
            moved["longitude"]=normalizedLongitude(park.longitude+shift)
            guard let data=try? JSONSerialization.data(withJSONObject:moved),
                  let stand=try? JSONDecoder().decode(Park.self,from:data) else { continue }
            let sky=HorizonSkies.shared.sky(park:stand,night:night.id,at:slot.addingTimeInterval(1))
            let renderer=ImageRenderer(content:PanoramaCanvas(sky:sky,options:options).frame(width:points.width,height:points.height))
            renderer.scale=scale
            renderer.isOpaque=true
            renderer.proposedSize=ProposedViewSize(points)
            if let image=renderer.cgImage { write(image,size:pixels,to:folder.appendingPathComponent(String(format:"%04d.png",index))) }
            if index%20==0 { log(root,"\(folder.lastPathComponent) \(index)/\(frames) \(instant) \(Int(Date.now.timeIntervalSince(clock)))s") }
            await Task.yield()
        }
        log(root,"\(folder.lastPathComponent) \(frames)/\(frames) from \(start) for \(Int(span/60)) min, \(Int(Date.now.timeIntervalSince(clock)))s")
    }
    private static func normalizedLongitude(_ value:Double)->Double {
        var v=value.truncatingRemainder(dividingBy:360)
        if v>180 { v-=360 }
        if v < -180 { v+=360 }
        return v
    }

    // MARK: The Moon

    private static func moon(park:Park,night:Night,folder:URL,root:URL) async {
        let frames=Int(DebugScenario.number("-nyx-promo-moon-frames") ?? 300)
        let thinnest=DebugScenario.number("-nyx-promo-moon-from") ?? 0.03
        let engine=AstronomyEngine()
        // One lunation from the night: the first waxing crescent at `thinnest`, to the last waning one.
        let hour=3600.0
        var first:Date?, last:Date?
        var previous=engine.moonGeometry(for:park,at:night.id)
        for step in 1..<(36*24) {
            let t=night.id.addingTimeInterval(Double(step)*hour), g=engine.moonGeometry(for:park,at:t)
            if first==nil, g.waxing==true, g.illumination>=thinnest, previous.illumination<thinnest { first=t }
            if first != nil, g.waxing==false, g.illumination<thinnest { last=t.addingTimeInterval(-hour); break }
            previous=g
        }
        guard let from=first, let to=last, to>from else { log(root,"moon: no lunation found"); return }
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let pixels=CGSize(width:1600,height:1600), scale=2.0, side=pixels.width/scale, disc=side*0.72
        let clock=Date.now
        for index in 0..<frames {
            let t=from.addingTimeInterval(to.timeIntervalSince(from)*Double(index)/Double(max(1,frames-1)))
            let g=engine.moonGeometry(for:park,at:t)
            // Lunar north up: the same Moon, turned so its axis is vertical in every frame. The disc is
            // 72% of the frame, so its halo (to 0.68 of the disc's side from the centre) fades out inside it.
            let upright=MoonGeometry(phaseAngle:g.phaseAngle,brightLimb:g.brightLimb-g.north,north:0,
                                     librationLongitude:g.librationLongitude,librationLatitude:g.librationLatitude,waxing:g.waxing)
            let content=ZStack { Color.black; MoonView(geometry:upright).frame(width:disc,height:disc) }.frame(width:side,height:side)
            let renderer=ImageRenderer(content:content)
            renderer.scale=scale
            renderer.isOpaque=true
            renderer.proposedSize=ProposedViewSize(width:side,height:side)
            if let image=renderer.cgImage { write(image,size:pixels,to:folder.appendingPathComponent(String(format:"%04d.png",index))) }
            if index%20==0 { log(root,"moon \(index)/\(frames) \(t) lit \(Int(g.illumination*100))% \(Int(Date.now.timeIntervalSince(clock)))s") }
            await Task.yield()
        }
        log(root,"moon \(frames)/\(frames) from \(from) to \(to), \(Int(Date.now.timeIntervalSince(clock)))s")
    }

    // MARK: Files

    private static func write(_ image:CGImage,size:CGSize,to url:URL) {
        guard image.width>=Int(size.width), image.height>=Int(size.height),
              let exact=image.cropping(to:CGRect(origin:.zero,size:size)),
              let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { return }
        CGImageDestinationAddImage(destination,exact,nil)
        CGImageDestinationFinalize(destination)
    }
    private static func log(_ root:URL,_ line:String) {
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("progress.txt")
        let text=(((try? String(contentsOf:url,encoding:.utf8)) ?? "")+line+"\n")
        try? text.write(to:url,atomically:true,encoding:.utf8)
    }
}
#endif
