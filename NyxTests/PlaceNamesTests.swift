import Foundation
import Testing
@testable import Nyx

/// Place names in the app's language: Wikidata's labels for world catalogue places, their
/// regions and the starting towns (`names-<lang>.json`). Each test
/// names its language, so none depends on the simulator's.
struct PlaceNamesTests {
    private static let eifel="wd:Q705097"
    private static let cevennes="wd:Q1368807"
    private static let fuji="wd:Q1137542"
    private static let teide="wd:Q715124"
    private static let etosha="wd:Q675633"
    private static func catalog(_ language: String) throws -> [Park] { try TestData.catalog(language: language) }
    private static func place(_ id: String, _ language: String) throws -> Park { try #require(try catalog(language).first { $0.id == id }) }

    // MARK: The files

    @Test(arguments: ["es", "de", "fr", "ja"]) func namesFilesDecode(language: String) throws {
        let names=PlaceNames.load(language: language)
        #expect(names.language == language && !names.isEmpty)
        #expect(names.places.count > 900 && names.regions.count > 1_000)
        // Built against the bundled towns, so their names apply.
        #expect(names.townCount == StartingPlaces.all.count)
        #expect(names.townNames(count: names.townCount).compactMap { $0 }.count > 2_000)
        let curated=Set(try ParkData.load().map(\.id))
        for (id, name) in names.places {
            #expect(id.hasPrefix(Park.catalogPrefix) && !curated.contains(id), "\(id)")
            #expect(!name.name.isEmpty && !name.short.isEmpty && name.name.contains(name.short), "\(id)")
            #expect(!name.name.contains("{") && !name.name.contains("}"), "\(id)")
        }
    }
    @Test func englishAndUnknownLanguagesHaveNoNames() {
        #expect(PlaceNames.load(language: "en").isEmpty && PlaceNames.load(language: "xx").isEmpty)
        #expect(PlaceNames.code("es-419") == "es" && PlaceNames.code("ja_JP") == "ja" && PlaceNames.code(nil) == "en")
        #expect(PlaceNames.load(language: "de-AT").language == "de")
    }
    /// Towns built against another list (a places.json rebuilt without the names) are never misnamed.
    @Test func townsApplyOnlyToTheListTheyWereBuiltFor() {
        let names=PlaceNames.load(language: "ja")
        #expect(names.townNames(count: names.townCount+1).allSatisfy { $0 == nil })
    }

    // MARK: Catalogue places

    @Test func aPlaceShowsItsNameInEachLanguage() throws {
        let english=try Self.place(Self.eifel, "en")
        #expect(english.name == "Eifel National Park" && english.shortName == "Eifel" && english.englishName == nil && english.region == "North Rhine-Westphalia")
        let german=try Self.place(Self.eifel, "de")
        #expect(german.name == "Nationalpark Eifel" && german.shortName == "Eifel" && german.region == "Nordrhein-Westfalen")
        #expect(german.englishName == "Eifel National Park" && german.englishRegion == "North Rhine-Westphalia")
        let french=try Self.place(Self.cevennes, "fr")
        #expect(french.name == "Parc national des Cévennes" && french.shortName == "Cévennes" && french.region == "Occitanie")
        let japanese=try Self.place(Self.fuji, "ja")
        #expect(japanese.name == "富士箱根伊豆国立公園" && japanese.shortName == "富士箱根伊豆" && japanese.region == "静岡県")
        let spanish=try Self.place(Self.teide, "es")
        #expect(spanish.name == "Parque Nacional del Teide" && spanish.shortName == "Teide" && spanish.region == "Canarias")
        // Everything but the words stays: the id, the point, the zone.
        #expect(german.id == english.id && german.latitude == english.latitude && german.timeZoneID == english.timeZoneID)
    }
    @Test func shortNamesStripTheDesignationInEachLanguage() {
        let cases: [(String, String, String)]=[
            ("Parque nacional {Budawang}", "Parque nacional Budawang", "Budawang"),
            ("Parque Nacional de la {Vanoise}", "Parque Nacional de la Vanoise", "Vanoise"),
            ("Nationalpark {Bayerischer Wald}", "Nationalpark Bayerischer Wald", "Bayerischer Wald"),
            ("{Etosha}-Nationalpark", "Etosha-Nationalpark", "Etosha"),
            ("Parc national d'{Etosha}", "Parc national d'Etosha", "Etosha"),
            ("Parc national des {lacs Thirlmere}", "Parc national des lacs Thirlmere", "lacs Thirlmere"),
            ("{富士箱根伊豆}国立公園", "富士箱根伊豆国立公園", "富士箱根伊豆"),
            ("Réserve internationale de ciel étoilé du Mont-Mégantic", "Réserve internationale de ciel étoilé du Mont-Mégantic", "Réserve internationale de ciel étoilé du Mont-Mégantic"),
        ]
        for (braced, name, short) in cases {
            let parsed=PlaceNames.name(braced: braced)
            #expect(parsed.name == name && parsed.short == short, "\(braced)")
        }
        for (language, id, short) in [("de", Self.etosha, "Etosha"), ("fr", Self.etosha, "Etosha"), ("es", Self.etosha, "Etosha"), ("ja", Self.etosha, "エトーシャ")] {
            #expect((try? Self.place(id, language))?.shortName == short, "\(language)")
        }
    }
    /// Labels that name another place or an older name are not used (the build's
    /// name overrides and its rule for renamed places): the place keeps its English name there.
    @Test func wrongAndOutdatedLabelsAreLeftOut() throws {
        let spanish=PlaceNames.load(language: "es"), german=PlaceNames.load(language: "de"), french=PlaceNames.load(language: "fr")
        // Jerusalem Walls is not the City of David; Migdal Afek is not the lordship of Mirabel.
        #expect(spanish.places["wd:Q2908664"] == nil && spanish.places["wd:Q568521"] == nil && french.places["wd:Q568521"] == nil)
        // Budj Bim, not Mount Eccles; Kalkajaka, not Black Mountain.
        #expect(german.places["wd:Q1950297"] == nil && french.places["wd:Q1950297"] == nil && french.places["wd:Q542749"] == nil)
        #expect(try Self.place("wd:Q1950297", "de").name == "Budj Bim National Park")
        // Nkasa Rupara, not Mamili.
        #expect(spanish.places["wd:Q1392554"]?.short == "Nkasa Rupara")
        // A short name starts with a capital.
        #expect(french.places["wd:Q3364499"]?.short == "Forêts")
        // Towns: the town, not its district or station.
        let towns=french.townNames(count: french.townCount)
        let hannover=try #require(StartingPlaces.all.firstIndex { $0.savedName == "Hannover" })
        #expect(towns[hannover] == "Hanovre")
        let spanishTowns=spanish.townNames(count: spanish.townCount)
        for (index, name) in spanishTowns.enumerated() { if let name { #expect(!name.contains("Municipio") && !name.contains("Estación"), "\(index)") } }
    }
    @Test func searchFindsAPlaceByItsLocalAndItsEnglishName() throws {
        let catalog=PlaceCatalog(try Self.catalog("de"))
        for query in ["Nationalpark Eifel", "eifel", "Eifel National Park", "Nordrhein-Westfalen", "North Rhine-Westphalia"] {
            #expect(catalog.search(Park.folded(query)).contains { $0.0.id == Self.eifel }, "\(query)")
        }
        let japan=PlaceCatalog(try Self.catalog("ja"))
        for query in ["富士箱根伊豆", "富士箱根伊豆国立公園", "Fuji-Hakone-Izu", "静岡県"] {
            #expect(japan.search(Park.folded(query)).contains { $0.0.id == Self.fuji }, "\(query)")
        }
        // Accents fold in French as in English.
        let french=try Self.place(Self.cevennes, "fr")
        #expect(french.matches("cevennes") && french.matches("Parc national des Cevennes") && french.matches("Cévennes National Park"))
    }
    /// A place travels whole to the widgets and the watch: its English name and short name go with it.
    @Test func aLocalNameSurvivesTheSnapshot() throws {
        let german=try Self.place(Self.eifel, "de")
        let back=try JSONDecoder().decode(Park.self, from: JSONEncoder().encode(german))
        #expect(back == german && back.shortName == "Eifel" && back.englishName == "Eifel National Park")
    }
    @Test(arguments: ["es", "de", "fr", "ja"]) func curatedParksKeepTheirEnglishNames(language: String) throws {
        let names=PlaceNames.load(language: language)
        for park in try ParkData.load() {
            let shown=park.named(in: names)
            #expect(shown == park && shown.name == park.name && shown.region == park.region, "\(park.id)")
        }
        // A US catalogue place keeps its postal-code region.
        for place in try Self.catalog(language) where place.countryCode == "US" { #expect(place.englishRegion == nil, "\(place.id)") }
    }

    // MARK: Starting towns

    @Test func aTownIsFoundAndShownInJapanese() throws {
        let towns=StartingPlaces.load(language: "ja")
        #expect(towns.count == StartingPlaces.all.count)
        let tokyo=try #require(StartingPlaces.search("東京", in: towns, limit: 5).first)
        #expect(tokyo.savedName == "Tokyo" && tokyo.countryCode == "JP" && tokyo.name.hasPrefix("東京"))
        #expect(tokyo.label.hasPrefix("東京"))
        // The English name still finds it, and it is the same place as in English.
        #expect(StartingPlaces.search("Tokyo", in: towns, limit: 5).contains(tokyo))
        let english=try #require(StartingPlaces.search("Tokyo", in: StartingPlaces.load(language: "en"), limit: 1).first)
        #expect(english == tokyo && english.id == tokyo.id && english.name == "Tokyo")
        // Saved as its bundled name, so a home chosen in Japanese is still Tokyo in English.
        let saved=try JSONSerialization.jsonObject(with: JSONEncoder().encode(tokyo)) as? [String: Any]
        #expect(saved?["name"] as? String == "Tokyo")
        let back=try JSONDecoder().decode(StartingPlace.self, from: JSONEncoder().encode(tokyo))
        #expect(back == tokyo)
    }
    @Test func aTownIsFoundByItsGermanName() throws {
        let towns=StartingPlaces.load(language: "de")
        let munich=try #require(StartingPlaces.search("München", in: towns, limit: 3).first { $0.countryCode == "DE" })
        #expect(munich.savedName == "Munich" && munich.name == "München")
        #expect(StartingPlaces.search("Munchen", in: towns, limit: 3).contains(munich))
        #expect(StartingPlaces.search("Munich", in: towns, limit: 3).contains(munich))
    }
    /// Japanese joins a place and its area with the ideographic comma; the others with ", ".
    @Test func placeAndAreaJoinAsTheLanguageWrites() {
        #expect(PlaceNames.joined("鹿児島県", "日本", language: "ja") == "鹿児島県、日本")
        #expect(PlaceNames.joined("Bayern", "Deutschland", language: "de") == "Bayern, Deutschland")
        #expect(PlaceNames.joined("Ontario", "Canada", language: "en") == "Ontario, Canada")
    }
}
