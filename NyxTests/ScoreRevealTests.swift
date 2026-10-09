import CoreGraphics
import Testing
@testable import Nyx

/// The dial has one composition per space offered: its band word and units go inside when the page
/// offers room for them, decided from that space and never from the dial's own measured side (which
/// shrinks when the words move below it and would keep them there).
@Suite struct ScoreRevealTests {
    @Test func tonightsHeroHoldsItsWordsInside() {
        #expect(CelestialGauge.labelsInside(offered:CGSize(width:240,height:240)))
        #expect(CelestialGauge.labelsInside(offered:CGSize(width:402,height:240)))
        #expect(CelestialGauge.labelsInside(offered:CGSize(width:300,height:300)))
    }
    @Test func onboardingsSmallDialKeepsItsWordsBelow() {
        #expect(!CelestialGauge.labelsInside(offered:CGSize(width:176,height:176)))
        #expect(!CelestialGauge.labelsInside(offered:CGSize(width:402,height:176)))
    }
    @Test func aNarrowColumnKeepsItsWordsBelowWhateverItsHeight() {
        #expect(!CelestialGauge.labelsInside(offered:CGSize(width:200,height:900)))
    }
    @Test func aHugeOfferIsCappedAtTheWidestPhonesDial() {
        #expect(CelestialGauge.labelsInside(offered:CGSize(width:1200,height:2000)))
    }
}
