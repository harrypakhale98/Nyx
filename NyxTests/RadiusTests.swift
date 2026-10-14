import Foundation
import Testing
@testable import Nyx

/// Tonight's radius is kept in metres and shown in the locale's unit: a radius chosen in miles
/// before survives exactly, US and UK locales keep miles, everywhere else counts in kilometres.
struct RadiusTests {
    let us=Locale(identifier: "en_US"), uk=Locale(identifier: "en_GB"), mexico=Locale(identifier: "es_MX"), germany=Locale(identifier: "de_DE")
    let mile=SearchRadius.metersPerMile
    private func defaults(_ name: String) throws -> UserDefaults {
        let defaults=try #require(UserDefaults(suiteName: "nyx-radius-\(name)"))
        defaults.removePersistentDomain(forName: "nyx-radius-\(name)")
        return defaults
    }
    /// The old caption, exactly as Tonight formatted it before metres.
    private func before(_ miles: Double, _ locale: Locale) -> String {
        Measurement(value: miles, unit: UnitLength.miles).formatted(Measurement<UnitLength>.FormatStyle(width: .abbreviated, locale: locale, usage: .road))
    }
    private func kilometers(_ value: Double, _ locale: Locale) -> String {
        Measurement(value: value, unit: UnitLength.kilometers).formatted(Measurement<UnitLength>.FormatStyle(width: .abbreviated, locale: locale, usage: .asProvided))
    }

    @Test func aRadiusInMilesBecomesTheSameMetresOnce() throws {
        let defaults=try defaults("migrate")
        defaults.set(500.0, forKey: SearchRadius.legacyKey)
        // Read before the move, after it, and again: always the same distance, exactly.
        #expect(SearchRadius.meters(defaults, locale: mexico) == 500*mile)
        SearchRadius.migrate(defaults)
        #expect(defaults.object(forKey: SearchRadius.key) as? Double == 500*mile)
        #expect(SearchRadius.meters(defaults, locale: mexico) == 500*mile && SearchRadius.meters(defaults, locale: us) == 500*mile)
        // A second launch changes nothing; the miles stay for an older build.
        SearchRadius.migrate(defaults)
        #expect(defaults.object(forKey: SearchRadius.key) as? Double == 500*mile && defaults.object(forKey: SearchRadius.legacyKey) as? Double == 500)
        // It is still one of the miles choices, so the menu ticks it.
        #expect(SearchRadius.steps(.miles).contains(SearchRadius.meters(defaults)))
        // A new choice wins over the old miles.
        SearchRadius.store(300_000, defaults)
        SearchRadius.migrate(defaults)
        #expect(SearchRadius.meters(defaults) == 300_000)
    }
    @Test func aWholeNumberOfMilesStoredAsAnIntegerStillReads() throws {
        let defaults=try defaults("integer")
        defaults.set(200, forKey: SearchRadius.legacyKey)
        SearchRadius.migrate(defaults)
        #expect(SearchRadius.meters(defaults) == 200*mile)
    }
    @Test func theStandardReachFollowsTheMeasurementSystem() throws {
        let defaults=try defaults("standard")
        #expect(SearchRadius.System(us) == .miles && SearchRadius.System(uk) == .miles)
        #expect(SearchRadius.System(mexico) == .kilometers && SearchRadius.System(germany) == .kilometers)
        #expect(SearchRadius.meters(defaults, locale: us) == 200*mile && SearchRadius.meters(defaults, locale: uk) == 200*mile)
        #expect(SearchRadius.meters(defaults, locale: mexico) == 300_000 && SearchRadius.meters(defaults, locale: germany) == 300_000)
        // Nothing is written until a person chooses: a change of region moves the standard with it.
        #expect(defaults.object(forKey: SearchRadius.key) == nil)
    }
    @Test func eachUnitHasItsOwnRoundSteps() {
        #expect(SearchRadius.steps(.miles) == [100, 200, 500, 1000].map { $0*mile })
        #expect(SearchRadius.steps(.kilometers) == [150_000, 300_000, 800_000, 1_500_000])
        #expect(SearchRadius.steps(.miles).contains(SearchRadius.standard(.miles)) && SearchRadius.steps(.kilometers).contains(SearchRadius.standard(.kilometers)))
        #expect(SearchRadius.wider(.miles) == 500*mile && SearchRadius.wider(.kilometers) == 800_000)
        #expect(SearchRadius.tripSteps(.miles) == [100, 200, 300, 500, 1000].map { $0*mile } && SearchRadius.tripSteps(.kilometers).count == 5)
        #expect(SearchRadius.hopSteps(.miles) == [100, 200, 300, 500].map { $0*mile } && SearchRadius.hopSteps(.kilometers).count == 4)
        #expect(SearchRadius.tripStandard(.miles) == 300*mile && SearchRadius.tripSteps(.kilometers).contains(SearchRadius.tripStandard(.kilometers)))
        // A radius set in the other unit is offered beside the steps, never replaced by one.
        let kept=SearchRadius.choices(SearchRadius.steps(.kilometers), keeping: 200*mile)
        #expect(kept.count == 5 && kept.contains(200*mile) && kept == kept.sorted())
        #expect(SearchRadius.choices(SearchRadius.steps(.miles), keeping: 200*mile) == SearchRadius.steps(.miles))
    }
    @Test func captionsReadAsBeforeInTheUSAndInKilometresElsewhere() {
        // US English: byte for byte what Tonight said before ("200 mi").
        for miles in [100.0, 200, 300, 500, 1000] { #expect(SearchRadius.label(miles*mile, locale: us) == before(miles, us)) }
        #expect(SearchRadius.label(200*mile, locale: us) == "200 mi")
        // The UK keeps miles.
        #expect(SearchRadius.label(200*mile, locale: uk) == before(200, uk) && SearchRadius.label(200*mile, locale: uk).contains("mi"))
        // Mexico and Germany count in kilometres, as chosen.
        for locale in [mexico, germany] {
            #expect(SearchRadius.label(300_000, locale: locale) == kilometers(300, locale))
            #expect(SearchRadius.label(1_500_000, locale: locale) == kilometers(1500, locale))
        }
        // A radius from the other unit is converted, rounded to ten and says so.
        #expect(SearchRadius.label(200*mile, locale: germany) == String(localized: "about \(kilometers(320, germany))", locale: germany))
        #expect(SearchRadius.label(300_000, locale: us) == String(localized: "about \(before(190, us))", locale: us))
    }
    @Test func askNyxCountsInTheLocalesUnit() throws {
        let parks=try ParkData.load()
        let lookup=NightLookup(parks: parks, forecasts: [:], now: Date(timeIntervalSince1970: 1_791_403_200))
        let km=lookup.parksNear(park: "Arches", radius: 250, system: .kilometers)
        #expect(km.contains { $0.hasPrefix("Canyonlands") } && km.allSatisfy { $0.contains(" km straight-line from Arches") })
        let distances=km.compactMap { $0.split(separator: ";").dropFirst().first?.split(separator: " ").first.flatMap { Int($0) } }
        #expect(distances.count == km.count && distances.allSatisfy { $0 <= 250 })
        #expect(lookup.parksNear(park: "American Samoa", radius: 100, system: .kilometers).first?.contains("0 km straight-line") == true)
        #expect(lookup.parksNear(park: "Arches", radius: 150, system: .miles).allSatisfy { $0.contains(" miles straight-line") })
        // Kept to 10–1,500 miles or 10–2,500 km.
        #expect(NightLookup.toolRadius(5, .miles) == 10 && NightLookup.toolRadius(2000, .miles) == 1500 && NightLookup.toolRadius(2000, .kilometers) == 2000 && NightLookup.toolRadius(9000, .kilometers) == 2500)
        #expect(lookup.parksNearLookup(park: "Joshua Tree", radius: 300, system: .kilometers) == "Parks near · Joshua Tree · within \(SearchRadius.format(300, .kilometers))")
        #expect(ParksNearTool(ledger: GuideLedger(firstID: 1), system: .kilometers).description.contains("kilometers"))
        #expect(ParksNearTool(ledger: GuideLedger(firstID: 1), system: .miles).description.contains("miles"))
    }
    @Test func launchReadsTheSameRadius() throws {
        let defaults=try defaults("launch")
        let parks=try ParkData.load()
        defaults.set(100.0, forKey: SearchRadius.legacyKey)
        let before=CachePreload.homeArea(parks, defaults: defaults).map(\.id)
        SearchRadius.migrate(defaults)
        #expect(CachePreload.homeArea(parks, defaults: defaults).map(\.id) == before && !before.isEmpty)
    }
}
