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
/// names draw against the frame), `-nyx-header-labels 0` (no star or Milky Way names: at store sizes
/// they are specks). Writes only a local file.
///
/// `-nyx-export-universal universal.png` (same arguments): the App Store's universal creative asset,
/// 5244 × 2950 pixels (16:9, no alpha), which fills both the product page header and the search
/// result. The same sky, with that night's own dial (`CelestialGauge`, still, drawing its night as on the park page) in the template's art
/// safe area (`safeArea`, the part every placement keeps), on a soft dark pool so the numeral reads
/// over the Milky Way. Tuning: `-nyx-universal-dial 300` (the dial's side in points),
/// `-nyx-universal-dial-x 0.5` / `-nyx-universal-dial-y 0.5` (its centre within the safe area),
/// `-nyx-universal-guides` (outlines the safe area, for review only). `-nyx-universal-dial 0` draws the
/// sky alone, the backdrop `Scripts/make_search_asset.swift` puts a screen on.
@MainActor enum DebugHeaderExport {
    static let pixels=CGSize(width:3840,height:1646)
    static let universalPixels=CGSize(width:5244,height:2950)
    /// Apple's universal template's "Art Safe Area", in pixels of the 5244 × 2950 canvas.
    static let safeArea=CGRect(x:1921,y:662,width:1399,height:957)
    static func runIfRequested(_ model:PlanModel) {
        if let name=DebugScenario.text("-nyx-export-universal") { universal(model,name:name); return }
        guard let name=DebugScenario.text("-nyx-export-header"), let park=model.home else { return }
        let night=model.night(park)
        let window=SkyAlmanac.nightWindow(night.sky)
        let minutes=DebugScenario.number("-nyx-header-minutes") ?? TonightSkyView.defaultMinutes(night.sky)
        let sky=HorizonSkies.shared.sky(park:park,night:night.id,at:window.start.addingTimeInterval(minutes*60))
        let options=PanoramaOptions(facing:DebugScenario.number("-nyx-header-facing") ?? 184,
                                    centreAltitude:DebugScenario.number("-nyx-header-altitude") ?? 22,
                                    span:DebugScenario.number("-nyx-header-span") ?? 1.1,
                                    labels:DebugScenario.number("-nyx-header-labels") != 0,
                                    bortle:Double(park.bortleEstimate))
        let scale=DebugScenario.number("-nyx-header-scale") ?? 3
        let points=CGSize(width:pixels.width/scale,height:pixels.height/scale)
        let renderer=ImageRenderer(content:PanoramaCanvas(sky:sky,options:options).frame(width:points.width,height:points.height))
        renderer.scale=scale
        renderer.isOpaque=true
        renderer.proposedSize=ProposedViewSize(points)
        guard let image=renderer.cgImage, image.width>=Int(pixels.width), image.height>=Int(pixels.height),
              let exact=image.cropping(to:CGRect(origin:.zero,size:pixels)) else { return }
        write(exact,name:name)
    }
    private static func universal(_ model:PlanModel,name:String) {
        guard let park=model.home else { return }
        let night=model.night(park)
        let window=SkyAlmanac.nightWindow(night.sky)
        let minutes=DebugScenario.number("-nyx-header-minutes") ?? TonightSkyView.defaultMinutes(night.sky)
        let sky=HorizonSkies.shared.sky(park:park,night:night.id,at:window.start.addingTimeInterval(minutes*60))
        let options=PanoramaOptions(facing:DebugScenario.number("-nyx-header-facing") ?? 184,
                                    centreAltitude:DebugScenario.number("-nyx-header-altitude") ?? 22,
                                    span:DebugScenario.number("-nyx-header-span") ?? 1.1,
                                    labels:DebugScenario.number("-nyx-header-labels") != 0,
                                    bortle:Double(park.bortleEstimate))
        let scale=DebugScenario.number("-nyx-header-scale") ?? 3
        let points=CGSize(width:universalPixels.width/scale,height:universalPixels.height/scale)
        let safe=CGRect(x:safeArea.minX/scale,y:safeArea.minY/scale,width:safeArea.width/scale,height:safeArea.height/scale)
        let side=DebugScenario.number("-nyx-universal-dial") ?? 300
        let centre=CGPoint(x:safe.minX+safe.width*(DebugScenario.number("-nyx-universal-dial-x") ?? 0.5),
                           y:safe.minY+safe.height*(DebugScenario.number("-nyx-universal-dial-y") ?? 0.5))
        let guides=DebugScenario.isEnabled("universal-guides")
        let art=ZStack(alignment:.topLeading) {
            PanoramaCanvas(sky:sky,options:options).frame(width:points.width,height:points.height)
            // Night itself behind the dial, as on the share card: the Milky Way fades out before the numeral.
            if side>0 {
                RadialGradient(colors:[.black.opacity(0.78),.black.opacity(0.45),.clear],center:.center,startRadius:0,endRadius:side*0.78)
                    .frame(width:side*1.6,height:side*1.6).position(centre)
                CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast,export:true,haptics:false,night:model.ring(night))
                    .frame(width:side,height:side).position(centre)
            }
            if guides { Rectangle().strokeBorder(.green,lineWidth:2).frame(width:safe.width,height:safe.height).position(x:safe.midX,y:safe.midY) }
        }
        .frame(width:points.width,height:points.height)
        .environment(\.colorScheme,.dark).dynamicTypeSize(.large)
        let renderer=ImageRenderer(content:art)
        renderer.scale=scale
        renderer.isOpaque=true
        renderer.proposedSize=ProposedViewSize(points)
        guard let image=renderer.cgImage, image.width>=Int(universalPixels.width), image.height>=Int(universalPixels.height),
              let exact=image.cropping(to:CGRect(origin:.zero,size:universalPixels)) else { return }
        write(exact,name:name)
    }
    private static func write(_ image:CGImage,name:String) {
        guard let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        let url=folder.appendingPathComponent((name as NSString).lastPathComponent)
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { return }
        CGImageDestinationAddImage(destination,image,nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
