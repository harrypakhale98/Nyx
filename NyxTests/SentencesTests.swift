import Foundation
import Testing
@testable import Nyx

/// Whole sentences set one after another: a space in English and the other Latin-script languages,
/// none after a Japanese sentence's "。". The language is passed in, so the result never depends on
/// the simulator's locale.
struct SentencesTests {
    @Test func latinLanguagesSeparateSentencesWithASpace() {
        for language in ["en", "de", "es", "fr"] {
            #expect(Sentences.join(["Clear sky.", "Moon down."], language: language) == "Clear sky. Moon down.")
        }
    }

    @Test func japaneseRunsSentencesTogether() {
        #expect(Sentences.join(["空は晴れています。", "月は沈んでいます。", "雲はありません。"], language: "ja") == "空は晴れています。月は沈んでいます。雲はありません。")
        #expect(Sentences.join(["晴れ。", "月は沈んでいる。"], language: "ja-JP") == "晴れ。月は沈んでいる。")
    }

    @Test func japaneseKeepsTheSpaceAfterPlainASCII() {
        // A Park Service headline ends in ASCII; the sentence after it must not stick to it.
        #expect(Sentences.join(["Road closed.", "月は沈んでいます。"], language: "ja") == "Road closed. 月は沈んでいます。")
    }

    @Test func emptyPartsAreDropped() {
        #expect(Sentences.join(["", "One.", "", "Two.", ""], language: "en") == "One. Two.")
        #expect(Sentences.join(["", "一。", "", "二。"], language: "ja") == "一。二。")
        #expect(Sentences.join([], language: "en") == "")
        #expect(Sentences.join(["Only."], language: "ja") == "Only.")
    }
    @Test func phrasesEndAsSentencesInTheirOwnScript() {
        #expect(Sentences.end("Moon-free all night", language: "en") == "Moon-free all night.")
        #expect(Sentences.end("Road closed.", language: "en") == "Road closed.")
        #expect(Sentences.end("一晩中月なし", language: "ja") == "一晩中月なし。")
        #expect(Sentences.end("一晩中月なし。", language: "ja") == "一晩中月なし。")
        #expect(Sentences.end("Road closed", language: "ja") == "Road closed.")
        #expect(Sentences.end("", language: "ja") == "")
        #expect(Sentences.end("月の輝面比82%", language: "ja") == "月の輝面比82%。")
        #expect(Sentences.end("82% lit", language: "en") == "82% lit.")
    }
    /// A time or date that ends in its own period ("9:04 p.m." in Latin American Spanish, "Sa. 31. Okt."
    /// in German) closes the sentence itself, never "p.m..".
    @Test func timesAndDatesThatEndInAPeriodTakeNoSecond() throws {
        let jotr=try park("jotr"), night=try date("2026-10-31 21:04", park: jotr)
        var time=Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "es_US"))
        time.timeZone=jotr.timeZone
        let late=night.formatted(time)
        #expect(late.hasSuffix("."))
        #expect(Sentences.end("Datos de las \(late)", language: "es") == "Datos de las \(late)")
        let day=jotr.dayLabel(night, locale: Locale(identifier: "de_DE"))
        #expect(day == "Sa. 31. Okt.")
        #expect(Sentences.end("Mein Plan für die Nacht: Joshua Tree, \(day)", language: "de").hasSuffix("Okt."))
        #expect(Phrase.sentences([day, "Vergangene Nacht"]) == "Sa. 31. Okt. Vergangene Nacht")
        // The Listen and Feel openings are two sentences, each closed once.
        let sky=AstronomyEngine().conditions(for: jotr, on: jotr.evening(night))
        let sound=NightSonification(park: jotr, sky: sky)
        #expect(sound.opening.hasPrefix("Joshua Tree, \(jotr.dayLabel(sky.evening)). 12 seconds of sound, from "))
        #expect(sound.opening.hasSuffix(".") && !sound.opening.contains(".."))
    }

    /// A sentence whose English ends in a full stop right after a value ("…, highest around 1:10 AM in
    /// the southeast.") keeps one in every language: the catalog leaves the stop off only where a time
    /// ends the sentence, and there the key has none and the code closes it (`Sentences.end`).
    @Test func sentencesEndingAfterAValueKeepTheirStopInEveryLanguage() throws {
        let url=try #require(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let english=try #require(NSDictionary(contentsOf: url) as? [String: String])
        let keys=english.keys.filter { $0.range(of: #"%(\d\$)?(@|lld|d)\.$"#, options: .regularExpression) != nil }
        #expect(keys.count>20)
        for language in ["es", "de", "fr", "ja"] {
            let bundle=try #require(Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)), "\(language)")
            for key in keys {
                let value=bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(value.hasSuffix(".") || value.hasSuffix("。"), "\(language): \(key) → \(value)")
            }
        }
        let es=try #require(Bundle.main.path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:)))
        #expect(es.localizedString(forKey: "Rises at %@ in the %@; highest around %@ in the %@.", value: nil, table: nil).hasSuffix("en el %4$@."))
    }
    /// A quieter thing in the sky with its gloss: a full stop and a space in English, "。" and no
    /// space in Japanese.
    @Test @MainActor func mentionsEndBeforeTheirGloss() {
        let item=WhatsUp.Item(id: "eclipse", kind: .eclipse, title: "Lunar eclipse", value: "1:04 – 2:12 AM", detail: "", spoken: "")
        #expect(WhatsUpPanel.mentionLine(item, gloss: "Partial: part of the Moon in Earth's darkest shadow.", language: "en") == "Lunar eclipse · 1:04 – 2:12 AM. Partial: part of the Moon in Earth's darkest shadow.")
        let ja=WhatsUp.Item(id: "eclipse", kind: .eclipse, title: "部分月食", note: "今夜", detail: "", spoken: "")
        #expect(WhatsUpPanel.mentionLine(ja, gloss: "月の一部が地球の濃い影に入ります。", language: "ja") == "部分月食 · 今夜。月の一部が地球の濃い影に入ります。")
        #expect(WhatsUpPanel.mentionLine(ja, gloss: nil, language: "ja") == "部分月食 · 今夜")
    }
    /// The Moon hero's line: a time that ends in "p.m." closes its sentence itself, and Japanese
    /// runs the sentences together with "。".
    @Test func moonHeroClosesEachTimeOnce() throws {
        let jotr=try park("jotr"), night=try date("2026-10-31 21:04", park: jotr)
        var time=Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "es_US"))
        time.timeZone=jotr.timeZone
        let late=night.formatted(time)
        let es=MoonHero.spoken(lit: "Creciente, con luz desde la derecha.", events: [(label: "Se pone", time: late)], language: "es")
        #expect(es == "Creciente, con luz desde la derecha. Se pone \(late)")
        #expect(!es.contains(".."))
        let ja=MoonHero.spoken(lit: "上弦、右側が明るい。", events: [(label: "昇る", time: "13:02"), (label: "沈む", time: "0:41")], language: "ja")
        #expect(ja == "上弦、右側が明るい。昇る 13:02。沈む 0:41。")
    }
    /// The river's value: the night's summary already ends in its own full stop, so the models'
    /// agreement and the sky event follow it without a second one ("forecast.. Forecast models agree").
    @Test func riverValueNeverDoublesAStop() throws {
        let en=TimeRiver.spokenValue(summary: "Fri, Oct 9, 94 out of 100, Pristine. Includes cloud forecast.", agreement: "Forecast models agree.", marker: "Geminids peak", language: "en")
        #expect(en == "Fri, Oct 9, 94 out of 100, Pristine. Includes cloud forecast. Forecast models agree. Geminids peak.")
        let jotr=try park("jotr")
        let day=jotr.dayLabel(try date("2026-10-31 21:04", park: jotr), locale: Locale(identifier: "de_DE"))
        let de=TimeRiver.spokenValue(summary: "\(day), 94 von 100, Makellos. Mit Wolkenvorhersage.", agreement: nil, marker: "Höhepunkt der Geminiden", language: "de")
        #expect(de.hasSuffix("Mit Wolkenvorhersage. Höhepunkt der Geminiden.") && !de.contains(".."))
        let fr=TimeRiver.spokenValue(summary: "sam. 31 oct., 94 sur 100, Parfaite. Prévision nuageuse comprise.", agreement: "Les modèles de prévision concordent.", marker: nil, language: "fr")
        #expect(fr == "sam. 31 oct., 94 sur 100, Parfaite. Prévision nuageuse comprise. Les modèles de prévision concordent.")
        let ja=TimeRiver.spokenValue(summary: "10月31日(土)、94点、最高。雲の予報を含みます。", agreement: "予報モデルは一致しています。", marker: "ふたご座流星群の極大", language: "ja")
        #expect(ja == "10月31日(土)、94点、最高。雲の予報を含みます。予報モデルは一致しています。ふたご座流星群の極大。")
    }
    /// Ask Nyx's distance under a place counts its miles: "1 mile", "1 Meile", never "1 Meilen".
    @Test func milesAreCountedInEveryLanguage() throws {
        let key="%lld miles straight-line from %@"
        let expected=["en": ("1 mile straight-line from Denver", "2 miles straight-line from Denver"),
                      "de": ("1 Meile Luftlinie von Denver", "2 Meilen Luftlinie von Denver"),
                      "es": ("1 milla en línea recta de Denver", "2 millas en línea recta de Denver"),
                      "fr": ("1 mile à vol d’oiseau depuis Denver", "2 miles à vol d’oiseau depuis Denver"),
                      "ja": ("Denverから直線距離で1マイル", "Denverから直線距離で2マイル")]
        for (language, (one, two)) in expected {
            let bundle=try #require(Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)), "\(language)")
            let format=bundle.localizedString(forKey: key, value: nil, table: nil)
            let locale=Locale(identifier: language)
            #expect(String(format: format, locale: locale, 1, "Denver") == one, "\(language)")
            #expect(String(format: format, locale: locale, 2, "Denver") == two, "\(language)")
        }
    }
    /// The parks-near record the model may quote, as `parksNearFacts` words it, holds that counted distance whole: "1 Meile", never "1 Meilen".
    @Test func parksNearRecordKeepsItsCountedDistance() throws {
        let expected=["en": "Arches, UT; 1 mile straight-line from Moab; tonight 88/100 Excellent",
                      "de": "Arches, UT; 1 Meile Luftlinie von Moab; heute Nacht 88/100 Excellent",
                      "es": "Arches, UT; a 1 milla en línea recta de Moab; esta noche 88/100 Excellent",
                      "fr": "Arches, UT\u{202F}; à 1 mile à vol d’oiseau depuis Moab\u{202F}; ce soir 88/100 Excellent",
                      "ja": "Arches、UT；Moabから直線距離で1マイル；今夜88/100 Excellent"]
        for (language, line) in expected {
            let bundle=try #require(Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)), "\(language)")
            let record=NightLookup.nearRecord("Arches", region: "UT", whole: 1, from: "Moab", score: 88, band: "Excellent", system: .miles, bundle: bundle, locale: Locale(identifier: language))
            #expect(record.line == line, "\(language)")
            #expect(record.line.contains(record.detail), "\(language)")
        }
        #expect(NightLookup.nearRecord("Arches", region: "UT", whole: 2, from: "Moab", score: 88, band: "Excellent", system: .kilometers).detail == "2 km straight-line from Moab")
    }
    /// Ask Nyx's "Looked up" lines read as sentences: a German date's own period is not doubled.
    @MainActor @Test func lookedUpLinesAreSpokenAsSentences() {
        #expect(GuideLookups.spoken(["Best nights · Arches · 30 nights from Oct 9", "Weather · Arches"]) == "Best nights · Arches · 30 nights from Oct 9. Weather · Arches")
        #expect(GuideLookups.spoken(["Beste Nächte · Arches · 30 Nächte ab Sa. 31. Okt.", "Wetter · Arches"]) == "Beste Nächte · Arches · 30 Nächte ab Sa. 31. Okt. Wetter · Arches")
        #expect(GuideLookups.spoken(["Weather · Arches"]) == "Weather · Arches")
    }
    /// The Moon phases met are a list in the reader's language, not names glued with an ASCII ", ".
    @MainActor @Test func phasesMetAreListed() {
        let names=[0, 4, 6].map { MoonPhase(fraction: YearRecap.phaseFraction($0)).name }
        #expect(names == ["New moon", "Full moon", "Last quarter"])
        #expect(MoonPhaseRow.spoken([6, 0, 4]) == "Phases met: \(names.formatted(.list(type: .and)))")
        #expect(MoonPhaseRow.spoken([0]) == "Phases met: New moon")
    }
    /// The satellite sky's line in Japanese: the class name closed with "。", no ASCII ". " after it.
    @Test func japaneseClassNameEndsInItsOwnMark() {
        #expect(Sentences.join([Sentences.end("郊外の空", language: "ja"), "衛星データからの推定です。"], language: "ja") == "郊外の空。衛星データからの推定です。")
        #expect(Sentences.join([Sentences.end("Suburban sky", language: "en"), "Estimated from satellite data."], language: "en") == "Suburban sky. Estimated from satellite data.")
    }
}
