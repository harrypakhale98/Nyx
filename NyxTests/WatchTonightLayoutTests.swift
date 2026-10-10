import SwiftUI
import Testing
@testable import Nyx

/// Apple Watch's Tonight face (`WatchTonightLayout`): fixed as designed at each watch's default
/// text size, scrolling at accessibility sizes, and in between fixed only while the dial keeps its
/// minimum under words that are never shrunk or cut.
struct WatchTonightLayoutTests {
    typealias Layout = WatchTonightLayout

    @Test func theStandardSizesStayFixedHoweverLittleRoomIsLeft() {
        #expect(Layout.choose(room: 150, words: 140, standardSize: true, accessibilitySize: false) == .fixed)
    }
    @Test func accessibilitySizesAlwaysScroll() {
        #expect(Layout.choose(room: 400, words: 20, standardSize: false, accessibilitySize: true) == .scrolling)
    }
    @Test func aLargeSizeStaysFixedWhileTheDialKeepsItsMinimum() {
        let words = 60.0, room = words + Layout.spacing + Layout.dialMinimum
        #expect(Layout.choose(room: room, words: words, standardSize: false, accessibilitySize: false) == .fixed)
        #expect(Layout.choose(room: room - 1, words: words, standardSize: false, accessibilitySize: false) == .scrolling)
    }
    @Test func tallWordsOnASmallFaceScroll() {
        // A face about as tall as the 40 mm one under its title, with three lines of large words.
        #expect(Layout.choose(room: 147, words: 96, standardSize: false, accessibilitySize: false) == .scrolling)
    }
    @Test func nothingMeasuredYetKeepsTheFaceFixed() {
        #expect(Layout.choose(room: 0, words: 80, standardSize: false, accessibilitySize: false) == .fixed)
        #expect(Layout.choose(room: 150, words: 0, standardSize: false, accessibilitySize: false) == .fixed)
    }
    @Test(arguments: [
        (197.0, DynamicTypeSize.large),   // 40 mm
        (223.0, .large),                  // 42 mm
        (224.0, .xLarge),                 // 44 mm, narrower than the 42 mm but one size larger
        (248.0, .xLarge),                 // 46 mm
        (257.0, .xLarge),                 // Ultra
    ])
    func eachWatchKeepsItsDefaultTextSizeAsDesigned(screenHeight: Double, defaultSize: DynamicTypeSize) {
        // Each watch's default text size, read from the watchOS 27 simulators, is the largest standard one.
        #expect(Layout.largestStandard(screenHeight: screenHeight) == defaultSize)
    }
    @Test func theScrollingDialIsNeverSmallerThanTheMinimum() {
        #expect(Layout.scrollingDial >= Layout.dialMinimum)
    }
}
