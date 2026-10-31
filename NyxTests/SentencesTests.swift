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

    /// A quieter thing in the sky with its gloss: a full stop and a space in English, "。" and no
    /// space in Japanese.
    @Test @MainActor func mentionsEndBeforeTheirGloss() {
        let item=WhatsUp.Item(id: "eclipse", kind: .eclipse, title: "Lunar eclipse", value: "1:04 – 2:12 AM", detail: "", spoken: "")
        #expect(WhatsUpPanel.mentionLine(item, gloss: "Partial: part of the Moon in Earth's darkest shadow.", language: "en") == "Lunar eclipse · 1:04 – 2:12 AM. Partial: part of the Moon in Earth's darkest shadow.")
        let ja=WhatsUp.Item(id: "eclipse", kind: .eclipse, title: "部分月食", note: "今夜", detail: "", spoken: "")
        #expect(WhatsUpPanel.mentionLine(ja, gloss: "月の一部が地球の濃い影に入ります。", language: "ja") == "部分月食 · 今夜。月の一部が地球の濃い影に入ります。")
        #expect(WhatsUpPanel.mentionLine(ja, gloss: nil, language: "ja") == "部分月食 · 今夜")
    }
    /// The satellite sky's line in Japanese: the class name closed with "。", no ASCII ". " after it.
    @Test func japaneseClassNameEndsInItsOwnMark() {
        #expect(Sentences.join([Sentences.end("郊外の空", language: "ja"), "衛星データからの推定です。"], language: "ja") == "郊外の空。衛星データからの推定です。")
        #expect(Sentences.join([Sentences.end("Suburban sky", language: "en"), "Estimated from satellite data."], language: "en") == "Suburban sky. Estimated from satellite data.")
    }
}
