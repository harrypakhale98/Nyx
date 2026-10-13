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
    }
}
