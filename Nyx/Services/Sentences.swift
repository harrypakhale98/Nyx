import Foundation

/// Whole sentences set one after another for display. English, German, Spanish and French part
/// them with a space; Japanese runs them together, since "。" already ends the sentence and a
/// space after it shows as a gap. Words and tokens that are not sentences keep their own joins.
nonisolated enum Sentences {
    /// The app's language, as `Lettering` reads it.
    static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    static func join(_ parts: [String]) -> String { join(parts, language: language) }

    static func end(_ text: String) -> String { end(text, language: language) }

    /// A phrase closed as a sentence, unless it already is: "。" in Japanese after Japanese text,
    /// "." otherwise (an English closure headline keeps its own full stop in any language).
    static func end(_ text: String, language: String) -> String {
        guard let last=text.last, !".!?…。！？".contains(last) else { return text }
        return language.hasPrefix("ja") && !last.isASCII ? text+"。" : text+"."
    }

    /// Empty parts are dropped. In Japanese no space follows a sentence that ends in a Japanese
    /// character or full-width mark; one that ends in plain ASCII (a closure headline from the
    /// Park Service, a figure) keeps its space so the next sentence does not stick to it.
    static func join(_ parts: [String], language: String) -> String {
        let kept=parts.filter { !$0.isEmpty }
        guard language.hasPrefix("ja") else { return kept.joined(separator:" ") }
        var out=""
        for part in kept {
            if let last=out.unicodeScalars.last, last.isASCII { out+=" " }
            out+=part
        }
        return out
    }
}
