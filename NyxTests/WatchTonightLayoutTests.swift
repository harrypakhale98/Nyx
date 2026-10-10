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
    @Test func eachWatchKeepsItsDefaultTextSizeAsDesigned() {
        // Large is the 40 mm's default (162 points wide), Extra Large the Ultra's (205).
        #expect(Layout.largestStandard(screenWidth: 162) == .large)
        #expect(Layout.largestStandard(screenWidth: 205) == .xLarge)
        #expect(DynamicTypeSize.xLarge > Layout.largestStandard(screenWidth: 162))
        #expect(DynamicTypeSize.xxLarge > Layout.largestStandard(screenWidth: 205))
    }
    @Test func theScrollingDialIsNeverSmallerThanTheMinimum() {
        #expect(Layout.scrollingDial >= Layout.dialMinimum)
    }
}
