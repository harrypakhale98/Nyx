import SwiftUI

/// Tonight beyond the score, on the wrist: the Milky Way's bright center, the planets, a meteor
/// shower, a lunar eclipse, aurora within reach by the forecast the iPhone handed over, and the
/// night's highlights, in the iPhone's own words (`WhatsUp`) and park-local times. Like
/// Milestones it is tonight's page; the Crown's later nights stay on the dial. Worked out on the
/// watch, off the main thread, from the bundled sky events; none of it changes the score.
struct WhatsUpPage: View {
    @Environment(\.nyx) private var palette
    @Environment(\.watchNow) private var now
    @Environment(WatchStore.self) private var store
    let night: Night
    /// False only in the loading preview, which holds the spinner.
    var computes = true
    /// What's up with the park and night it was worked out for (`key`): another park's sky is never
    /// shown while this one's is being worked out.
    @State private var worked: (key: String, value: WhatsUp)?
    /// The park, the night and the aurora forecast it was worked out with: a new forecast redoes it.
    private func key(_ night: Night) -> String {
        "\(night.park.id)-\(Int(night.id.timeIntervalSince1970))-\(Int(store.context?.aurora?.updated.timeIntervalSince1970 ?? 0))"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                WatchEyebrow(text: "What's up tonight")
                if let worked, worked.key == key(night) { content(worked.value) }
                else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                        .accessibilityLabel(Text("Working out tonight's sky"))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: key(night)) {
            guard computes, worked?.key != key(night) else { return }
            let park = night.park, sky = night.sky, id = key(night), outlook = store.context?.aurora, moment = now
            let value = await Task.detached(priority: .userInitiated) {
                WhatsUp(park: park, sky: sky, isTonight: true, aurora: AuroraForecast.item(outlook, park: park, sky: sky, now: moment))
            }.value
            if !Task.isCancelled { worked = (key: id, value: value) }
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
            Text("No bright planets up in true darkness tonight.").font(.caption2).foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true).nonEssential()
        }
        if !layout.mentions.isEmpty {
            divider
            ForEach(layout.mentions) { item in mention(item) }
        }
        if night.park.keepsOtherTime(at: now) {
            Text("Times in \(night.park.timeZoneName)").font(.caption2).foregroundStyle(palette.muted).nonEssential()
        }
    }
    private var divider: some View { Rectangle().fill(palette.line).frame(height: 0.5).padding(.vertical, 1).accessibilityHidden(true) }
    /// A name (with a word such as "very bright" or "peak tonight"), the figure to read at a glance,
    /// in ink, then one plain sentence. VoiceOver reads the iPhone's spoken form, which says ranges
    /// as "from … to …".
    private func row(_ item: WhatsUp.Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            let title = Text(item.title).font(.system(.body, design: .serif)).foregroundStyle(palette.ink)
            if let note = item.note { Text("\(title) · \(Text(note).font(.caption2).foregroundStyle(palette.muted))") } else { title }
            if let value = item.value {
                Text(value).font(.system(.subheadline, design: .serif)).monospacedDigit().foregroundStyle(palette.ink)
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

/// Which of tonight's items are rows and which a line at the foot: the iPhone card's own rule
/// (`WhatsUp.layout`), so both list the same things in the same order.
struct WristWhatsUp {
    var rows: [WhatsUp.Item]
    var mentions: [WhatsUp.Item]
    /// Nothing worth timing tonight: no planets, no timed core, nothing worth a row after them.
    var quiet: Bool
    init(_ whatsUp: WhatsUp) {
        let layout = whatsUp.layout
        rows = layout.first + whatsUp.planets + layout.after
        mentions = layout.mentions
        quiet = whatsUp.planets.isEmpty && layout.after.isEmpty && layout.first.count == 1 && !whatsUp.core.timed
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
