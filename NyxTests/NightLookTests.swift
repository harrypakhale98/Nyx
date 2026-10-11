import Foundation
import SwiftUI
import Testing
@testable import Nyx

/// One night look on every surface outside the app: the widgets, the Live Activity, the alarm and
/// Siri's cards take night vision and the brighter red from the shared settings, and Increase
/// Contrast from the view. Siri names a closure before the score.
@MainActor struct NightLookTests {
    /// A throwaway suite, so the tests never touch the App Group's real settings.
    func defaults(nightVision: Bool, brighterRed: Bool=false) throws -> UserDefaults {
        let name="NightLookTests-\(UUID().uuidString)"
        let suite=try #require(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suite.set(nightVision, forKey: NightLook.nightVisionKey)
        suite.set(brighterRed, forKey: NightTint.key)
        return suite
    }

    @Test func standardRedByDefault() throws {
        let look=try NightLook(defaults: defaults(nightVision: true))
        #expect(look.nightVision && look.red == .standard)
        #expect(look.inkRGB == NightTint.standard.rgb && look.accentRGB == NightTint.standard.rgb)
        #expect(look.mutedOpacity == 0.9)
        #expect(look.palette == NyxPalette(nightVision: true, highContrast: false))
    }
    @Test func brighterRedWhenChosen() throws {
        let look=try NightLook(defaults: defaults(nightVision: true, brighterRed: true))
        #expect(look.red == .brighter && look.inkRGB == NightTint.brighter.rgb)
        #expect(look.palette.red == .brighter)
    }
    @Test func increasedContrastLiftsTheRedAndTheSecondaryText() throws {
        let look=try NightLook(defaults: defaults(nightVision: true), contrast: .increased)
        #expect(look.highContrast && look.red == .brighter && look.inkRGB == NightTint.brighter.rgb)
        #expect(look.mutedOpacity == 1)
        // The lifted red still reads at 4.5:1 or more on black for protan and deutan eyes.
        for vision in ColorVision.allCases { #expect(vision.contrast(look.inkRGB, SIMD3(0, 0, 0))>=4.5) }
        let day=try NightLook(defaults: defaults(nightVision: false), contrast: .increased)
        #expect(day.mutedOpacity == 0.9)
    }
    @Test func starlightAndAmberWithNightVisionOff() throws {
        let look=try NightLook(defaults: defaults(nightVision: false, brighterRed: true))
        #expect(!look.nightVision)
        #expect(look.inkRGB == NightLook.starlight && look.accentRGB == NightLook.amber)
        #expect(look.mutedOpacity == 0.7)
    }
    @Test func aSurfaceCarryingItsOwnSwitchKeepsIt() throws {
        // A widget's entry or a Live Activity's state says whether night vision was on when it was made.
        let suite=try defaults(nightVision: true, brighterRed: true)
        #expect(!NightLook(defaults: suite, nightVision: false).nightVision)
        let red=FieldActivityColors(nightVision: true, contrast: .increased)
        #expect(red.look.red == .brighter && red.look.nightVision)
    }

    // MARK: Siri

    @Test func darknessDialogNamesTheClosureFirst() throws {
        let jotr=try #require(try ParkData.load().first(where: { $0.id == "jotr" }))
        let now=Date(timeIntervalSince1970: 1_796_158_800)
        let plain=DarknessAnswer(park: jotr, forecast: nil, detail: nil, now: now)
        let closed=DarknessAnswer(park: jotr, forecast: nil, detail: nil, closure: "Keys View Road closed at night", now: now)
        #expect(closed.dialog.hasPrefix("Closure alert: Keys View Road closed at night. "))
        #expect(closed.dialog.hasSuffix(plain.dialog))
        #expect(closed.night.score.value == plain.night.score.value)
        // A headline that already ends a sentence keeps its own stop.
        #expect(DarknessAnswer.dialog(plain.night, closure: "Park closed.", voiceOnly: false).hasPrefix("Closure alert: Park closed. "))
        #expect(DarknessAnswer.dialog(plain.night, closure: "  ", voiceOnly: false) == plain.dialog)
    }
    @Test func voiceOnlyDarknessAnswerIsShortAndKeepsTheClosure() throws {
        let jotr=try #require(try ParkData.load().first(where: { $0.id == "jotr" }))
        let now=Date(timeIntervalSince1970: 1_796_158_800)
        let night=DarknessAnswer(park: jotr, forecast: nil, detail: nil, now: now).night
        let voice=DarknessAnswer.dialog(night, closure: "Keys View Road closed at night", voiceOnly: true)
        #expect(voice.hasPrefix("Closure alert: Keys View Road closed at night. Tonight at \(jotr.shortName): \(night.score.value), \(night.score.band.label)."))
        #expect(!voice.contains("Confirm conditions"))
        #expect(DarknessAnswer.dialog(night, closure: nil, voiceOnly: true).hasPrefix("Tonight at \(jotr.shortName): "))
    }
}
