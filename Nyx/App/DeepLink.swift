import Foundation

/// Every `nyx://` link Nyx answers: widgets, Spotlight, the field Live Activity, calendar events
/// it drafted, and App Store In-App Events. Parsing is pure, so each form is tested; park ids are
/// checked against the bundled parks by whoever opens the link.
nonisolated enum DeepLink: Equatable, Sendable {
    /// `nyx://park/<id>`
    case park(String)
    /// `nyx://tonight`
    case tonight
    /// `nyx://field/<id>`
    case field(String)
    /// `nyx://whatsup?date=YYYY-MM-DD&park=<id>`: that night at the park, opened at What's up.
    case whatsUp(park: String, day: TripDay)
    /// `nyx://calendar/<id>?month=YYYY-MM`: the park's month in Calendar (this month without `month`).
    case calendar(park: String, year: Int?, month: Int?)

    init?(_ url: URL) {
        guard url.scheme?.lowercased()=="nyx", let host=url.host()?.lowercased() else { return nil }
        let path=url.pathComponents.filter { $0 != "/" }
        let query=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        func item(_ name: String) -> String? { query.first { $0.name==name }?.value?.trimmingCharacters(in:.whitespaces) }
        func parkID(_ raw: String?) -> String? {
            guard let raw=raw?.lowercased(), (2...8).contains(raw.count), raw.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
            return raw
        }
        switch host {
        case "park": guard let id=parkID(path.first) else { return nil }; self = .park(id)
        case "tonight": self = .tonight
        case "field": guard let id=parkID(path.first) else { return nil }; self = .field(id)
        case "whatsup":
            guard let id=parkID(item("park")), let day=item("date").flatMap(TripDay.init(iso:)) else { return nil }
            self = .whatsUp(park:id,day:day)
        case "calendar":
            guard let id=parkID(path.first) else { return nil }
            guard let month=item("month") else { self = .calendar(park:id,year:nil,month:nil); return }
            let parts=month.split(separator:"-")
            guard parts.count==2, parts[0].count==4, let y=Int(parts[0]), let m=Int(parts[1]), (1...12).contains(m), (1900...2200).contains(y) else { return nil }
            self = .calendar(park:id,year:y,month:m)
        default: return nil
        }
    }
    var url: URL? {
        switch self {
        case .park(let id): URL(string:"nyx://park/\(id)")
        case .tonight: URL(string:"nyx://tonight")
        case .field(let id): URL(string:"nyx://field/\(id)")
        case .whatsUp(let park,let day): URL(string:"nyx://whatsup?date=\(day.iso)&park=\(park)")
        case .calendar(let park,let year?,let month?): URL(string:String(format:"nyx://calendar/%@?month=%04d-%02d",park,year,month))
        case .calendar(let park,_,_): URL(string:"nyx://calendar/\(park)")
        }
    }
}
/// A request from a link for the Calendar tab to show one park's month. `id` changes with every
/// request, so the same link opened twice still moves the calendar back to that month.
struct CalendarRequest: Equatable {
    let id=UUID()
    let parkID: String
    let year: Int?
    let month: Int?
}
