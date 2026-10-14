import Foundation

/// A place id from outside the app (a link, a Handoff from another device, a complication's tap), in
/// its stored form, or nil for anything else: a park's letters (`jotr`, any case), a Wikidata item
/// (`wd:Q123456`) or a saved spot (`pin:` and a UUID, stored lowercase). The colon may arrive
/// percent-encoded (`wd%3AQ123456`). One rule for the iPhone, the watch and Vision Pro.
nonisolated enum PlaceIDText {
    static func validated(_ raw: String) -> String? {
        let raw=raw.contains("%") ? (raw.removingPercentEncoding ?? raw) : raw
        let parts=raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count==1 {
            guard (2...8).contains(raw.count), raw.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
            return raw.lowercased()
        }
        let rest=parts[1]
        switch parts[0].lowercased() {
        case "wd":
            let digits=rest.dropFirst()
            guard rest.first?.lowercased()=="q", (1...12).contains(digits.count), digits.first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return "wd:Q\(digits)"
        case "pin":
            guard rest.count==36, let uuid=UUID(uuidString: String(rest)) else { return nil }
            return "pin:\(uuid.uuidString.lowercased())"
        default: return nil
        }
    }
}
