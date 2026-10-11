import SwiftUI

/// Tonight beyond the score, on the wrist: the Milky Way's bright center, the planets, a meteor
/// shower and a lunar eclipse, in the iPhone's own words (`WhatsUp`) and park-local times. Like
/// Milestones it is tonight's page; the Crown's later nights stay on the dial. Worked out on the
/// watch, off the main thread, from the bundled sky events; none of it changes the score.
struct WhatsUpPage: View {
    @Environment(\.nyx) private var palette
    @Environment(\.watchNow) private var now
    let night: Night
    /// False only in the loading preview, which holds the spinner.
    var computes = true
    /// What's up with the park and night it was worked out for (`key`): another park's sky is never
    /// shown while this one's is being worked out.
    @State private var worked: (key: String, value: WhatsUp)?
    private static func key(_ night: Night) -> String { "\(night.park.id)-\(Int(night.id.timeIntervalSince1970))" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                WatchEyebrow(text: "What's up tonight")
                if let worked, worked.key == Self.key(night) { content(worked.value) }
                else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                        .accessibilityLabel(Text("Working out tonight's sky"))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: Self.key(night)) {
            guard computes, worked?.key != Self.key(night) else { return }
            let park = night.park, sky = night.sky, key = Self.key(night)
            let value = await Task.detached(priority: .userInitiated) { WhatsUp(park: park, sky: sky, isTonight: true) }.value
            if !Task.isCancelled { worked = (key: key, value: value) }
        }
    }
    @ViewBuilder private func content(_ whatsUp: WhatsUp) -> some View {
        let layout = WristWhatsUp(whatsUp)
        if layout.quiet {
            // Nothing timed in the dark hours: said once, calmly, before the core's own reason.
            Label { Text("A quiet sky tonight") } icon: { Image(systemName: "moon.stars") }
                .font(.system(.body, design: .serif)).foregroundStyle(palette.ink)
        }
        ForEach(layout.rows) { item in
            if item.id != layout.rows.first?.id { divider }
            row(item)
        }
        if whatsUp.planets.isEmpty {
            Text("No bright planets up in the dark hours tonight.").font(.caption2).foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true).nonEssential()
        }
        if !layout.mentions.isEmpty {
            divider
            ForEach(layout.mentions) { item in mention(item) }
        }
        if night.park.timeZone.secondsFromGMT(for: now) != TimeZone.current.secondsFromGMT(for: now) {
            Text("Times in \(night.park.timeZoneName)").font(.caption2).foregroundStyle(palette.muted).nonEssential()
        }
    }
    private var divider: some View { Rectangle().fill(palette.line).frame(height: 0.5).padding(.vertical, 1).accessibilityHidden(true) }
    /// A name (with a word such as "very bright" or "peak tonight"), the figure to read at a glance,
    /// in the accent when it is a time the thing is up, then one plain sentence. VoiceOver reads the
    /// iPhone's spoken form, which says ranges as "from … to …".
    private func row(_ item: WhatsUp.Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            let title = Text(item.title).font(.system(.body, design: .serif)).foregroundStyle(palette.ink)
            if let note = item.note { Text("\(title) · \(Text(note).font(.caption2).foregroundStyle(palette.muted))") } else { title }
            if let value = item.value {
                Text(value).font(.system(.subheadline, design: .serif)).monospacedDigit().foregroundStyle(item.timed ? palette.accent : palette.ink)
            }
            Text(item.detail).font(.caption2).foregroundStyle(palette.muted).nonEssential()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.spoken))
    }
    /// A quieter thing in the sky, one line: "October Draconids · about 2 an hour".
    private func mention(_ item: WhatsUp.Item) -> some View {
        Text(verbatim: [item.title, item.value ?? item.note].compactMap { $0 }.joined(separator: " · "))
            .font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true).nonEssential()
            .accessibilityLabel(Text(item.spoken))
    }
}

/// Which of tonight's items are rows and which a line at the foot, by the iPhone card's rule
/// (`WhatsUpPanel.layout`): a total eclipse the park can see leads, then the core and the planets,
/// then a shower of ten or more an hour and a partial eclipse; weaker showers, a penumbral eclipse
/// and one the park cannot see are mentions.
struct WristWhatsUp {
    var rows: [WhatsUp.Item]
    var mentions: [WhatsUp.Item] = []
    /// Nothing worth timing tonight: no planets, no timed core, no shower or eclipse worth a row.
    var quiet: Bool
    /// Showers under this many an hour are a mention, as on the iPhone.
    static let showerRow = 10
    init(_ whatsUp: WhatsUp) {
        var first = [whatsUp.core], after: [WhatsUp.Item] = []
        if let shower = whatsUp.shower {
            if (whatsUp.events.shower?.hourlyRate ?? 0) >= Self.showerRow { after.append(shower) } else { mentions.append(shower) }
        }
        if let eclipse = whatsUp.eclipse, let night = whatsUp.events.eclipse {
            if night.visible == nil || night.eclipse.type == "penumbral" { mentions.append(eclipse) }
            else if night.eclipse.type == "total" { first.insert(eclipse, at: 0) }
            else { after.append(eclipse) }
        }
        rows = first + whatsUp.planets + after
        quiet = whatsUp.planets.isEmpty && after.isEmpty && first.count == 1 && !whatsUp.core.timed
    }
}

/// Previews: Joshua Tree from the real engine on chosen nights.
private func previewNight(_ id: String, _ year: Int, _ month: Int, _ day: Int, store: WatchStore) -> Night? {
    guard let park = store.park(id), let evening = park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
    return WatchSky.night(park, evening: evening, forecast: nil, detail: nil, now: evening)
}
#Preview("What's up • tonight, red") {
    WatchPreviewHost(nightVision: true) { park, store in WhatsUpPage(night: store.tonight(park, at: .now)) }
}
#Preview("What's up • Geminids peak") {
    WatchPreviewHost(nightVision: false) { _, store in
        if let night = previewNight("jotr", 2026, 12, 13, store: store) { WhatsUpPage(night: night) }
    }
}
#Preview("What's up • partial eclipse") {
    WatchPreviewHost(nightVision: true) { _, store in
        if let night = previewNight("jotr", 2026, 8, 27, store: store) { WhatsUpPage(night: night) }
    }
}
#Preview("What's up • quiet, Denali in June") {
    WatchPreviewHost(nightVision: false) { _, store in
        if let night = previewNight("dena", 2026, 6, 21, store: store) { WhatsUpPage(night: night) }
    }
}
#Preview("What's up • AX5") {
    WatchPreviewHost(nightVision: true) { park, store in WhatsUpPage(night: store.tonight(park, at: .now)) }
        .dynamicTypeSize(.accessibility5)
}
#Preview("What's up • Always-On") {
    WatchPreviewHost(nightVision: false) { park, store in WhatsUpPage(night: store.tonight(park, at: .now)) }
        .environment(\.isLuminanceReduced, true)
}
#Preview("What's up • loading") {
    WatchPreviewHost(nightVision: true) { park, store in WhatsUpPage(night: store.tonight(park, at: .now), computes: false) }
}
