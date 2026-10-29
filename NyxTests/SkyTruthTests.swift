import Foundation
import Testing
@testable import Nyx

/// One sky truth on every device: the same "is the Moon in the way?" rule and the same words for
/// the Moon in true darkness on the iPhone, the watch and Vision Pro; one best-night window; one
/// muted text level for night vision.
struct SkyTruthTests {
    private let engine = AstronomyEngine()
    /// The phase lit by `illumination` (waxing).
    private static func phase(lit illumination: Double) -> MoonPhase { MoonPhase(fraction: acos(1-2*illumination)/(2*Double.pi)) }
    /// `base` with its Moon, rise, set or Moon-free share replaced (`.some(nil)` clears a rise or set).
    private static func sky(_ base: SkyConditions, moon: MoonPhase? = nil, rise: Date?? = nil, set: Date?? = nil, below: Double? = nil) -> SkyConditions {
        SkyConditions(evening: base.evening, end: base.end, sunset: base.sunset, sunrise: base.sunrise, civilDusk: base.civilDusk,
                      nauticalDusk: base.nauticalDusk, darkStart: base.darkStart, darkEnd: base.darkEnd, state: base.state,
                      moon: moon ?? base.moon, moonrise: rise ?? base.moonrise, moonset: set ?? base.moonset,
                      moonBelowFraction: below ?? base.moonBelowFraction, darkHours: base.darkHours, moonlight: base.moonlight, lowestSun: base.lowestSun)
    }
    /// A Joshua Tree night with the real Moon up through all of true darkness (near full, autumn 2026).
    private func moonlitNight(_ jotr: Park) throws -> SkyConditions {
        let first = try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        return try #require((0..<60).lazy.map { self.engine.conditions(for: jotr, on: jotr.date(first, addingDays: $0)) }.first { $0.darkHours > 3 && $0.moonDownPercent == 0 })
    }

    // MARK: A Moon too thin to matter

    /// The threshold is the number shown: "5% lit" matters, "4% lit" does not.
    @Test func negligibleFollowsThePercentShown() {
        let four = Self.phase(lit: 0.044), five = Self.phase(lit: 0.046)
        #expect(four.percentLit == 4 && four.negligible)
        #expect(five.percentLit == 5 && !five.negligible)
        #expect(five.litText == String(localized: "\(Percent.text(5)) lit"))
        #expect(four.spoken == "\(four.name), 4 percent lit" && four.spoken.hasPrefix("Waxing crescent"))
    }
    /// `moonHidden` is the phase rule, then the refracted horizon.
    @Test func moonHiddenIsThinOrBelowTheHorizon() throws {
        let jotr = try park("jotr"), night = try moonlitNight(jotr)
        let middle = try #require(night.darkStart).addingTimeInterval(night.darkHours*1800)
        #expect(engine.lunarAltitude(at: middle, park: jotr) > 0)
        #expect(!engine.moonHidden(at: middle, park: jotr, phase: night.moon))
        #expect(engine.moonHidden(at: middle, park: jotr, phase: Self.phase(lit: 0.03)))
    }
    /// A 3% crescent up all through true darkness: the watch's next dark is the whole of true darkness,
    /// never "Dark, Moon up", and a crossing of a Moon that does not matter never splits it.
    @Test func thinMoonUpAllNightIsDarkOnTheWrist() throws {
        let jotr = try park("jotr"), real = try moonlitNight(jotr)
        let start = try #require(real.darkStart), end = try #require(real.darkEnd)
        // The real Moon makes it moonlit, so the fixture tests the phase rule and nothing else.
        #expect(DarkMoment.next(at: jotr, now: start.addingTimeInterval(-1800), sky: { _ in real }) == .moonlit(from: start, to: end))
        let thin = Self.sky(real, moon: Self.phase(lit: 0.03), rise: .some(nil), set: start.addingTimeInterval(3600))
        #expect(thin.moon.percentLit == 3)
        #expect(DarkMoment.next(at: jotr, now: start.addingTimeInterval(-1800), sky: { _ in thin }) == .begins(start, moonset: false))
        #expect(DarkMoment.next(at: jotr, now: start.addingTimeInterval(5400), sky: { _ in thin }) == .darkNow(until: end, moonrise: false))
        // The iPhone says the same of it.
        #expect(thin.moonInDarkness == .negligible)
        #expect(thin.moonShort(park: jotr) == "Almost no moonlight")
        #expect(thin.moonSentence(park: jotr) == "Moon too thin to matter, \(Percent.text(3)) lit.")
    }
    /// The watch's milestones list moonrise and moonset as the iPhone's field night does: only for
    /// a Moon that matters, and only inside the night.
    @Test func milestonesSkipANegligibleMoon() throws {
        let jotr = try park("jotr"), real = try moonlitNight(jotr)
        let sunset = try #require(real.sunset), sunrise = try #require(real.sunrise)
        let rise = sunset.addingTimeInterval(3600), set = sunrise.addingTimeInterval(-3600)
        let kinds = { (sky: SkyConditions) in Set(NightMilestone.list(for: sky).map(\.kind)) }
        let thin = Self.sky(real, moon: Self.phase(lit: 0.03), rise: rise, set: set)
        #expect(kinds(thin).isDisjoint(with: [.moonrise, .moonset]))
        let full = Self.sky(real, moon: MoonPhase(fraction: 0.5), rise: rise, set: set)
        #expect(kinds(full).isSuperset(of: [.moonrise, .moonset]))
        // A rise after sunrise is the next day's, not tonight's.
        let late = Self.sky(real, moon: MoonPhase(fraction: 0.5), rise: sunrise.addingTimeInterval(3600), set: .some(nil))
        #expect(!kinds(late).contains(.moonrise))
    }

    // MARK: The Moon in true darkness

    @Test func moonInDarknessCasesAndWords() throws {
        let jotr = try park("jotr"), real = try moonlitNight(jotr)
        let start = try #require(real.darkStart), full = MoonPhase(fraction: 0.5), lit = Percent.text(100)
        let set = start.addingTimeInterval(7200)
        let cases: [(SkyConditions, MoonInDarkness, String?, String?, String)] = [
            (Self.sky(real, moon: full, below: 1), .allFree, "Moon-free through all of true darkness.", "Moon-free through all of true darkness.", "Moon down"),
            (Self.sky(real, moon: full, below: 0), .allUp, "Moon up all through true darkness, \(lit) lit.", "Moon up all through true darkness.", "Dark, Moon up"),
            (Self.sky(real, moon: full, rise: .some(nil), set: set, below: 0.6), .setsAt(set),
             "Moon up until \(jotr.time(set)), \(lit) lit.", "Moon up until \(jotr.time(set)).", "Moon down at \(jotr.time(set))"),
            (Self.sky(real, moon: full, rise: set, set: .some(nil), below: 0.4), .risesAt(set),
             "Moon rises at \(jotr.time(set)), \(lit) lit.", "Moon rises at \(jotr.time(set)).", "Dark until \(jotr.time(set))"),
            (Self.sky(real, moon: full, rise: .some(nil), set: .some(nil), below: 0.5), .partial(percentFree: 50),
             "Moon-free for 50% of true darkness.", "Moon-free for 50% of true darkness.", "Moon-free for 50% of true darkness"),
        ]
        for (sky, kind, long, bare, short) in cases {
            #expect(sky.moonInDarkness == kind)
            #expect(sky.moonSentence(park: jotr) == long)
            #expect(sky.moonSentence(park: jotr, withLit: false) == bare)
            #expect(sky.moonShort(park: jotr) == short)
            // The verdict under the dial says exactly this.
            #expect(sky.moonSentence(park: jotr) == long)
        }
        // A Moon that sets and rises again inside true darkness is neither a moonset nor a moonrise.
        let back = start.addingTimeInterval(9000)
        #expect(Self.sky(real, moon: full, rise: back, set: set, below: 0.5).moonInDarkness == .partial(percentFree: 50))
        // All of the dark Moon-free comes first, even for a Moon too thin to matter.
        #expect(Self.sky(real, moon: Self.phase(lit: 0.02), below: 1).moonInDarkness == .allFree)
        let dena = try park("dena")
        let june = engine.conditions(for: dena, on: try #require(dena.calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))))
        #expect(june.moonInDarkness == .noDarkness && june.moonSentence(park: dena) == nil && june.moonShort(park: dena) == "No true darkness")
    }
    /// The reminder and the trip planner use the glance words.
    @Test func remindersAndTripsUseTheGlanceWords() throws {
        let jotr = try park("jotr"), real = try moonlitNight(jotr)
        let free = NightPlanner.night(park: jotr, sky: Self.sky(real, moon: MoonPhase(fraction: 0.5), below: 1), forecast: nil, detail: nil, now: real.evening)
        #expect(NotificationScheduler.reason(free) == "Moon down")
        #expect(TripPlanner.reason(free).hasPrefix("Moon down, "))
        // A Moon up all through true darkness is never the reason a reminder gives.
        let up = NightPlanner.night(park: jotr, sky: real, forecast: nil, detail: nil, now: real.evening)
        #expect(!NotificationScheduler.reason(up).contains("Moon"))
        #expect(TripPlanner.reason(up).hasPrefix("Dark, Moon up, \(real.moon.litText), "))
        #expect(!TripPlanner.reason(free).contains(free.sky.moon.litText))
    }

    // MARK: One window, one best night

    /// "No true darkness in the next 30 nights" only when no night searched has any: a dark night
    /// under cloud ranked below clear twilit nights still has true darkness.
    @Test func noDarknessCountsEveryNightSearched() throws {
        let dena = try park("dena")
        let august = try #require(dena.calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        // The first night of the season with true darkness, and three twilit nights before it.
        let firstDark = try #require((0..<60).map { dena.date(august, addingDays: $0) }.first { engine.conditions(for: dena, on: $0).darkHours > 0 })
        let now = dena.date(firstDark, addingDays: -3).addingTimeInterval(6*3600)
        let skies = (0..<6).map { engine.conditions(for: dena, on: dena.date(firstDark, addingDays: $0-3)) }
        // Overcast through every stretch of true darkness, clear otherwise.
        let dark = skies.compactMap { sky in sky.darkStart.flatMap { s in sky.darkEnd.map { DateInterval(start: s.addingTimeInterval(-3600), end: $0.addingTimeInterval(3600)) } } }
        let hours = (0..<(20*24)).map { now.timeIntervalSince1970-86400+Double($0)*3600 }
        let forecast = Forecast(updated: now, times: hours, clouds: hours.map { t in dark.contains { $0.contains(Date(timeIntervalSince1970: t)) } ? 100 : 0 })
        let planner = NightPlanner(forecasts: [dena.id: forecast])
        let ahead = NightsAhead(park: dena, planner: planner, now: now, count: 6, limit: 3)
        try #require(ahead.picks.count == 3 && ahead.picks.allSatisfy { $0.night.sky.darkHours == 0 })
        try #require(planner.nights(dena, from: now, count: 6, now: now).contains { $0.sky.darkHours > 0 })
        #expect(!ahead.noDarkness)
    }
    /// `NightPlanner.best` is the first of `ranked` in any order the nights come in, ties included
    /// (a month on the usual clouds holds many equal scores).
    @Test func bestIsTheFirstRankedNight() throws {
        let jotr = try park("jotr"), now = try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18)))
        let nights = NightPlanner(forecasts: [:]).nights(jotr, from: now, count: NightPlanner.horizon, now: now)
        let first = try #require(NightPlanner.ranked(nights).first)
        for order in [nights, nights.reversed(), nights.shuffled()] {
            #expect(NightPlanner.best(order)?.id == first.id)
        }
    }

    // MARK: Night vision's muted text

    @Test func mutedOpacityIsOneRule() {
        #expect(NyxPalette.mutedOpacity(nightVision: false, highContrast: false) == 0.72)
        #expect(NyxPalette.mutedOpacity(nightVision: false, highContrast: true) == 0.9)
        #expect(NyxPalette.mutedOpacity(nightVision: true, highContrast: false) == 0.96)
        #expect(NyxPalette.mutedOpacity(nightVision: true, highContrast: true) == 1)
        for nightVision in [false, true] {
            for highContrast in [false, true] {
                #expect(NightLook(nightVision: nightVision, highContrast: highContrast).mutedOpacity == NyxPalette.mutedOpacity(nightVision: nightVision, highContrast: highContrast))
                // Faint is a starlight level only: in red, and under Increase Contrast, it is muted.
                let faint = NyxPalette.faintOpacity(nightVision: nightVision, highContrast: highContrast)
                #expect(faint == (nightVision || highContrast ? NyxPalette.mutedOpacity(nightVision: nightVision, highContrast: highContrast) : 0.62))
            }
        }
        // Muted red text on black reads at 4.5:1 or better for typical, protan and deutan eyes alike;
        // the 90% widgets used before fell under it for protan eyes.
        for vision in ColorVision.allCases {
            #expect(vision.contrast(NightTint.standard.rgb*NyxPalette.mutedOpacity(nightVision: true, highContrast: false), .zero) >= 4.5)
        }
        #expect(ColorVision.protan.contrast(NightTint.standard.rgb*0.9, .zero) < 4.5)
    }
}
