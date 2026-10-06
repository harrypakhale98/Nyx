import Foundation
import Testing
import simd
@testable import Nyx

/// iPad: which widths get two columns, and the compass seen through a screen in landscape.
@Suite struct IPadTests {
    // MARK: Layout

    @Test func twoColumnsOnlyWhereTheyFit() {
        // iPhone 18 Pro, iPad mini portrait, 11-inch portrait: one column.
        for width in [402.0,744,834] { #expect(WideLayout.columns(width:width,largeText:false)==1) }
        // 13-inch portrait (1032), 11-inch landscape (1194), 13-inch landscape (1376): two.
        for width in [1032.0,1194,1376] { #expect(WideLayout.columns(width:width,largeText:false)==2) }
        // Half of a 13-inch landscape screen beside another app stays one column.
        #expect(WideLayout.columns(width:688,largeText:false)==1)
        // Accessibility text sizes need about twice the room before the page splits.
        #expect(WideLayout.columns(width:1032,largeText:true)==1)
        #expect(WideLayout.columns(width:1376,largeText:true)==2)
    }
    @Test func theHeroColumnStaysInBounds() {
        #expect(WideLayout.leadingWidth(900)==400)
        #expect(WideLayout.leadingWidth(1376)==520)
        let middle=WideLayout.leadingWidth(1100)
        #expect(middle>400 && middle<520 && middle<=1100/2)
        // Whole points, so a two-column page never chases a fraction of a point (1032 × 0.42 = 433.44).
        #expect(WideLayout.leadingWidth(1032)==433)
        #expect(WideLayout.margin(width:402,measure:WideLayout.readableWidth)==0)
        #expect(WideLayout.margin(width:1100,measure:700)==200)
    }

    // MARK: Compass in landscape

    private func same(_ a:SkyCompass.Pose,_ b:SkyCompass.Pose)->Bool {
        simd_distance(a.look,b.look)<1e-9 && simd_distance(a.up,b.up)<1e-9 && simd_distance(a.right,b.right)<1e-9
    }
    /// Core Motion reports the device's own axes. An iPad held in landscape with its top to the left
    /// (interface landscape right) is the upright pose rolled a quarter anticlockwise; turned back
    /// by the interface, the screen sees the sky upright again. Likewise the other two turns.
    @Test func theInterfaceTurnUndoesTheDevicesRoll() {
        let upright=SkyCompass.Pose(azimuth:200,altitude:35)
        #expect(same(SkyCompass.Pose(azimuth:200,altitude:35,roll:-90).turned(1),upright))
        #expect(same(SkyCompass.Pose(azimuth:200,altitude:35,roll:180).turned(2),upright))
        #expect(same(SkyCompass.Pose(azimuth:200,altitude:35,roll:90).turned(3),upright))
        #expect(same(upright.turned(0),upright) && same(upright.turned(4),upright) && same(upright.turned(-1),upright.turned(3)))
        // Turning never changes where the device points, only which way is up on the screen.
        #expect(simd_distance(upright.turned(1).look,upright.look)<1e-12)
        // In landscape, a higher target is up the (wide) screen, not to its side.
        let w=1376.0, h=1032.0
        let pose=SkyCompass.Pose(azimuth:180,altitude:30,roll:-90).turned(1)
        let higher=SkyCompass.place(altitude:40,azimuth:180,pose:pose,width:w,height:h,fieldOfView:SkyCompass.horizontalFieldOfView(width:w,height:h))
        #expect((higher.point?.y ?? h)<h/2-20 && abs((higher.point?.x ?? 0)-w/2)<1e-6)
    }
    /// The shorter side always spans the compass's 60°: a phone in portrait is unchanged, an iPad in
    /// landscape sees more sky to each side at the same scale.
    @Test func theShorterSideSpansSixtyDegrees() {
        #expect(SkyCompass.horizontalFieldOfView(width:402,height:874)==SkyCompass.fieldOfView)
        #expect(SkyCompass.horizontalFieldOfView(width:1032,height:1376)==SkyCompass.fieldOfView)
        let wide=SkyCompass.horizontalFieldOfView(width:1376,height:1032)
        #expect(wide>SkyCompass.fieldOfView && wide<90)
        // A target 30° above the centre sits on the top edge.
        let pose=SkyCompass.Pose(azimuth:180,altitude:30)
        let edge=SkyCompass.place(altitude:60,azimuth:180,pose:pose,width:1376,height:1032,fieldOfView:wide,clipped:false)
        #expect(abs((edge.point?.y ?? 99)-0)<1e-6)
    }
}
