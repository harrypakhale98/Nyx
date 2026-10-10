#if DEBUG
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// `-nyx-export-header header.png` (with `-nyx-screen detail -nyx-park deva -nyx-date 2027-07-03`):
/// draws the App Store product page header, 3840 × 1646 pixels with no alpha, from the same
/// `PanoramaCanvas` the full-screen "Tonight's sky" uses, and writes it to the app's Documents
/// folder under that name. The scene is the store set's: the night's default hour (the middle of
/// true darkness, 12:55 AM), facing just west of south (184°) so the core sits mid-frame, the
/// horizon low and the Milky Way rising from it. No header, controls or status bar. Tuning, for retakes: `-nyx-header-facing 184`,
/// `-nyx-header-altitude 22`, `-nyx-header-span 1.1` (as `PanoramaOptions`), `-nyx-header-minutes N`
/// (after the night's start), `-nyx-header-scale 3` (pixels per point: sets how large stars and
/// names draw against the frame). Writes only a local file.
@MainActor enum DebugHeaderExport {
    static let pixels=CGSize(width:3840,height:1646)
    static func runIfRequested(_ model:PlanModel) {
        guard let name=DebugScenario.text("-nyx-export-header"), let park=model.home else { return }
        let night=model.night(park)
        let window=SkyAlmanac.nightWindow(night.sky)
        let minutes=DebugScenario.number("-nyx-header-minutes") ?? TonightSkyView.defaultMinutes(night.sky)
        let sky=HorizonSkies.shared.sky(park:park,night:night.id,at:window.start.addingTimeInterval(minutes*60))
        let options=PanoramaOptions(facing:DebugScenario.number("-nyx-header-facing") ?? 184,
                                    centreAltitude:DebugScenario.number("-nyx-header-altitude") ?? 22,
                                    span:DebugScenario.number("-nyx-header-span") ?? 1.1,
                                    bortle:Double(park.bortleEstimate))
        let scale=DebugScenario.number("-nyx-header-scale") ?? 3
        let points=CGSize(width:pixels.width/scale,height:pixels.height/scale)
        let renderer=ImageRenderer(content:PanoramaCanvas(sky:sky,options:options).frame(width:points.width,height:points.height))
        renderer.scale=scale
        renderer.isOpaque=true
        renderer.proposedSize=ProposedViewSize(points)
        guard let image=renderer.cgImage, image.width>=Int(pixels.width), image.height>=Int(pixels.height),
              let exact=image.cropping(to:CGRect(origin:.zero,size:pixels)),
              let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        let url=folder.appendingPathComponent((name as NSString).lastPathComponent)
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { return }
        CGImageDestinationAddImage(destination,exact,nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
