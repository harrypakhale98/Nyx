import SwiftUI

/// The month's name in the reader's language, 1–12.
nonisolated private var gregorian: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.locale = .current; return calendar }
nonisolated private func monthName(_ month: Int) -> String {
    let names = gregorian.standaloneMonthSymbols
    return names.indices.contains(month-1) ? names[month-1] : ""
}
nonisolated extension NightAccess.Rule {
    /// The rule's mark: a gate at night, a road under snow, a ticket.
    var symbol: String {
        switch kind {
        case "nightClosure": "moon.zzz"
        case "seasonalRoad": "snowflake"
        default: "ticket"
        }
    }
    /// "Usually closed in October" / "In effect in October", when the rule names months and this is one.
    func monthLine(_ month: Int) -> String? {
        guard months != nil, applies(inMonth: month) else { return nil }
        return kind == "seasonalRoad" ? String(localized: "Usually closed in \(monthName(month))") : String(localized: "In effect in \(monthName(month))")
    }
}

/// "After dark": what the Park Service says about getting to the park's dark skies at night and
/// through the year, each rule with its page; a rule usually in effect in the month of the night
/// shown says so beside the caution glyph. Usual patterns only: tonight's closures are the park alerts'.
struct AfterDarkPanel: View {
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    let park: Park
    /// The month of the night shown, 1–12.
    let month: Int
    var access: NightAccess = .shared
    var body: some View {
        let rules = access.rules(park.id)
        if !rules.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "After dark")
                    ForEach(rules) { rule in row(rule) }
                    Text("Usual patterns from the Park Service, not live road status. Closures in force tonight are in the park's alerts.")
                        .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func row(_ rule: NightAccess.Rule) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title).font(.subheadline.weight(.medium)).foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
                if let line = rule.monthLine(month) { Text(line).font(.caption.weight(.medium)).foregroundStyle(palette.ink) }
                Text(rule.note).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                if let url = rule.source {
                    Button { openURL(url) } label: { Text("Park Service page").font(.caption).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                        .foregroundStyle(palette.ink)
                        .accessibilityHint("Opens nps.gov in Safari.")
                }
            }
        } icon: { Image(systemName: rule.symbol).foregroundStyle(rule.monthLine(month) == nil ? palette.ink : palette.caution).accessibilityHidden(true) }
    }
}

/// "Busy and quiet months": twelve small bars of the Park Service's monthly recreation visits, the
/// month of the night shown in starlight, the rest as hairlines, and the pattern in one sentence. Decorative bars; the
/// sentence is what VoiceOver reads.
struct BusyMonthsPanel: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var barHeight = 40.0
    let park: Park
    let month: Int
    var visits: ParkVisits = .shared
    var body: some View {
        if let months = visits.parks[park.id], months.visits.count == 12, let top = months.visits.max(), top > 0 {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Busy and quiet months")
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<12, id: \.self) { i in
                            VStack(spacing: 4) {
                                Capsule().fill(i == month-1 ? palette.ink : palette.line)
                                    .frame(height: max(3, barHeight*Double(months.visits[i])/Double(top)))
                                // Twelve letters do not fit at accessibility sizes; the sentence below says the pattern.
                                if !typeSize.isAccessibilitySize {
                                    Text(gregorian.veryShortStandaloneMonthSymbols[i]).font(.caption2.weight(i == month-1 ? .semibold : .regular)).foregroundStyle(i == month-1 ? palette.ink : palette.muted)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                    Text(Self.summary(months, month: month)).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
                    Text("Recreation visits counted by the Park Service, monthly averages for 2021 to 2025. Counting changed at a few parks in those years, so only the pattern is shown.")
                        .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    /// "Busiest in July; quietest in January, February and December. October is one of the quietest months here."
    nonisolated static func summary(_ months: ParkVisits.Months, month: Int) -> String {
        let quiet = months.quietest.map(monthName).formatted(.list(type: .and))
        let pattern = String(localized: "Busiest in \(monthName(months.busiest)); quietest in \(quiet).")
        let this: String = switch months.level(month: month) {
        case .busy: String(localized: "\(monthName(month)) is one of the busiest months here.")
        case .quiet: String(localized: "\(monthName(month)) is one of the quietest months here.")
        case .between: ""
        }
        return Sentences.join([pattern, this])
    }
}

#Preview("After dark · Glacier in May") {
    if let p = try? ParkData.load().first(where: { $0.id == "glac" }) { ScrollView { AfterDarkPanel(park: p, month: 5).padding() }.background(.black).preferredColorScheme(.dark) }
}
#Preview("After dark · AX5") {
    if let p = try? ParkData.load().first(where: { $0.id == "acad" }) { ScrollView { AfterDarkPanel(park: p, month: 7).padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
}
#Preview("Busy months · Death Valley in October") {
    if let p = try? ParkData.load().first(where: { $0.id == "deva" }) { ScrollView { BusyMonthsPanel(park: p, month: 10).padding() }.background(.black).preferredColorScheme(.dark) }
}
#Preview("Busy months · night vision") {
    if let p = try? ParkData.load().first(where: { $0.id == "yell" }) {
        ScrollView { BusyMonthsPanel(park: p, month: 1).padding() }.background(.black)
            .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true)).preferredColorScheme(.dark)
    }
}
#Preview("No data · a park without rules") {
    if let p = try? ParkData.load().first(where: { $0.id == "cong" }) { ScrollView { AfterDarkPanel(park: p, month: 5).padding() }.background(.black).preferredColorScheme(.dark) }
}
