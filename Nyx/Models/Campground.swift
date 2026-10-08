import Foundation

/// A campground from the NPS API (`/api/v1/campgrounds`, fields verified against a live response
/// on 2026-10-07): only what "Where to stay" shows. Nyx never knows availability; it shows the
/// National Park Service's own description and hands reservations to Safari.
nonisolated struct Campground: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Lower-case NPS park code ("jotr").
    let parkCode: String
    /// The first sentence of the NPS description, tidied; empty when there is none.
    let summary: String
    /// A reservation page on recreation.gov or nps.gov only; other hosts are left out.
    let reservationURL: URL?
    /// The campground's own page on nps.gov.
    let pageURL: URL?
    let reservableSites: Int?
    let firstComeSites: Int?
    let totalSites: Int?
    /// The NPS "wheelchair access" note, first sentence, when one is given.
    let wheelchairAccess: String?
    /// The NPS ADA note, first sentence, when one is given.
    let adaNote: String?

    /// Hosts whose pages Nyx opens in Safari for a reservation: the federal booking site and the
    /// park service's own pages. Anything else (a concessioner's booking engine with tracking
    /// parameters) is not linked; the person can still find it from the park's page.
    static let reservationHosts: Set<String> = ["recreation.gov", "www.recreation.gov", "nps.gov", "www.nps.gov"]
    static func allowed(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              var parts = URLComponents(string: text), let host = parts.host?.lowercased(), reservationHosts.contains(host),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? "") else { return nil }
        // Always over HTTPS, and never with a tracking query or fragment.
        parts.scheme = "https"; parts.host = host; parts.fragment = nil
        parts.queryItems = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && $0.name != "_ga" }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.url
    }
    /// "Reserve on Recreation.gov" or "Reserve on nps.gov", by the link's host.
    var reservationSite: String? {
        guard let host = reservationURL?.host() else { return nil }
        return host.hasSuffix("recreation.gov") ? "Recreation.gov" : "nps.gov"
    }
    /// The first sentence of an NPS text, with list dashes, stars and stray spaces removed.
    static func firstSentence(_ text: String) -> String {
        var clean = ParkStore.plain(text).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        clean = clean.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—•")))
        guard !clean.isEmpty else { return "" }
        // A sentence ends at ". ", "! " or "? " followed by a capital, never inside "approx. 5" or "St. Mary".
        var end = clean.endIndex
        var search = clean.startIndex
        while let range = clean.range(of: #"[.!?] (?=[A-Z0-9“"])"#, options: .regularExpression, range: search..<clean.endIndex) {
            let before = clean[clean.startIndex..<range.lowerBound].split(separator: " ").last.map(String.init) ?? ""
            if ["St", "Mt", "Ft", "approx", "Hwy", "Rd", "No", "U.S", "Jr", "Dr"].contains(before) { search = range.upperBound; continue }
            end = clean.index(after: range.lowerBound); break
        }
        let sentence = String(clean[clean.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        // One long run-on line is cut at a word near 220 characters, so a card never becomes a page.
        guard sentence.count > 220 else { return sentence }
        let cut = sentence.prefix(220)
        return (cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? String(cut)) + "…"
    }

    /// One page of `/api/v1/campgrounds`. Numbers arrive as strings ("62"); missing or odd values
    /// become nil rather than failing the page. Records without a name or park code are skipped.
    struct Page: Sendable {
        let campgrounds: [Campground]
        let total: Int?
        let count: Int
    }
    static func page(_ data: Data) throws -> Page {
        struct Record: Decodable {
            let id: String?
            let name: String?
            let parkCode: String?
            let description: String?
            let url: String?
            let reservationUrl: String?
            let numberOfSitesReservable: String?
            let numberOfSitesFirstComeFirstServe: String?
            let campsites: Sites?
            let accessibility: Access?
            struct Sites: Decodable { let totalSites: String? }
            struct Access: Decodable { let wheelchairAccess: String?; let adaInfo: String? }
        }
        struct Response: Decodable { let data: [Record]; let total: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        func number(_ text: String?) -> Int? { text.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 >= 0 ? $0 : nil } }
        func note(_ text: String?) -> String? { text.map(firstSentence).flatMap { $0.isEmpty ? nil : $0 } }
        let campgrounds = response.data.compactMap { r -> Campground? in
            guard let name = r.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let code = r.parkCode?.lowercased().trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
            return Campground(id: r.id ?? "\(code)-\(name)", name: name, parkCode: code, summary: firstSentence(r.description ?? ""),
                              reservationURL: allowed(r.reservationUrl), pageURL: allowed(r.url),
                              reservableSites: number(r.numberOfSitesReservable), firstComeSites: number(r.numberOfSitesFirstComeFirstServe),
                              totalSites: number(r.campsites?.totalSites), wheelchairAccess: note(r.accessibility?.wheelchairAccess), adaNote: note(r.accessibility?.adaInfo))
        }
        return Page(campgrounds: campgrounds, total: response.total.flatMap { Int($0) }, count: response.data.count)
    }
}
/// Every park's campgrounds from one request, keyed by NPS park code, fresh for seven days.
nonisolated struct CampgroundsCache: Codable, Sendable, Equatable {
    let updated: Date
    let campgrounds: [String: [Campground]]
    /// A park's campgrounds, reservable ones first, then by name.
    func list(_ park: Park) -> [Campground] {
        (campgrounds[park.apiCode] ?? []).sorted { a, b in
            let ra = (a.reservableSites ?? 0) > 0, rb = (b.reservableSites ?? 0) > 0
            return ra != rb ? ra : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
