import Foundation

/// Sentences and clauses joined as the reader's language punctuates them, from catalog templates
/// rather than punctuation written in code: Japanese gets "。" and "、" where English has ". " and ", ".
nonisolated enum Phrase {
    /// Sentences one after another: "Clear. Moon down" in English, "晴れ。月は沈んでいる" in Japanese.
    /// A sentence that already ends with its own full stop is not given a second one.
    static func sentences(_ parts: [String]) -> String {
        join(parts) { String(localized: "\(open($0)). \($1)") }
    }
    /// Clauses of one sentence: "Excellent night, clouds not known yet".
    static func clauses(_ parts: [String]) -> String {
        join(parts) { String(localized: "\($0), \($1)") }
    }
    /// A clause added after a semicolon: "Best window: 11:40 PM – 3:10 AM; Milky Way core up throughout".
    static func addition(_ first: String, _ second: String) -> String {
        second.isEmpty ? first : String(localized: "\(first); \(second)")
    }
    /// A sentence given its closing full stop: "On your Lock Screen now, until dawn." / "…。"
    static func ended(_ sentence: String) -> String { String(localized: "\(sentence).") }
    /// Names in a list, as the language writes one: "Arches, Bryce Canyon, and Zion"; "アーチーズ、ブライスキャニオン、ザイオン".
    static func list(_ names: [String]) -> String { names.formatted(.list(type: .and)) }
    /// The sentence without a closing full stop of its own, so a join never doubles it.
    private static func open(_ sentence: String) -> String {
        sentence.hasSuffix("。") || (sentence.hasSuffix(".") && !sentence.hasSuffix("...")) ? String(sentence.dropLast()) : sentence
    }
    private static func join(_ parts: [String], _ pair: (String, String) -> String) -> String {
        let kept=parts.filter { !$0.isEmpty }
        guard let first=kept.first else { return "" }
        return kept.dropFirst().reduce(first, pair)
    }
}
