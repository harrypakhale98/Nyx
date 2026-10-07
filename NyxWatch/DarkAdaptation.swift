import SwiftUI
import UserNotifications

/// Field mode on the wrist: red only, black everywhere. A 30-minute dark-adaptation clock the
/// wearer starts (a tap, or Double Tap), with wrist taps at 25 and 30 minutes, and below it the
/// next moment of the night. The why lives behind the info button, not on the screen.
struct DarkAdaptationView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let park: Park
    @State private var showsInfo = false
    @State private var permission: UNAuthorizationStatus?
    private let palette = NyxPalette(nightVision: true, highContrast: false)
    var body: some View {
        // Its own stack, filtered as a whole: the system's close button would otherwise be the one
        // white thing on the screen. A dark, red-glyphed Done replaces it.
        NavigationStack {
            content.modifier(WatchDebug.AlwaysOn()).modifier(WatchDebug.ScrollEnd())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Label("Done", systemImage: "xmark") }.tint(palette.toolbarTint)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsInfo = true } label: { Label("About dark adaptation", systemImage: "info") }.tint(palette.toolbarTint)
                    }
                    // Start and Stop sit in the bottom bar, so the ring and the next moment share one screen.
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        control
                        Spacer()
                    }
                }
                .sheet(isPresented: $showsInfo) { AdaptationInfo().environment(\.nyx, palette).modifier(NightVisionFilter(enabled: true)) }
        }
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .environment(\.nyx, palette)
        .modifier(NightVisionFilter(enabled: true))
        .background(Color.black)
        .task { permission = await AdaptationReminders.status() }
        .onAppear { store.reloadSettings() }
    }
    private var content: some View {
        // Minutes counted from the moment the clock started, not from the wall clock's minute.
        TimelineView(.periodic(from: store.adaptation?.start ?? .now, by: 60)) { timeline in
            let now = timeline.date
            let clock = store.adaptation
            let night = store.tonight(park, at: now)
            let next = NightMilestone.next(after: now, in: night.sky)
            ScrollView {
                // Words above the ring: the bottom bar's button then rests in the ring's opening.
                VStack(spacing: 4) {
                    if clock == nil, permission == .notDetermined {
                        // Asked in context, once: the system prompt follows this line the first time.
                        Text("Nyx will ask to tap your wrist at 25 and 30 minutes.").font(.caption2).foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true).nonEssential()
                    } else if let next {
                        NextInDark(night: night, next: next, now: now)
                    } else {
                        Text("Nothing more tonight").font(.footnote).foregroundStyle(palette.muted).nonEssential()
                    }
                    AdaptationRing(clock: clock, now: now).frame(maxWidth: 112)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // At large text sizes the page scrolls; this keeps its end clear of the button.
                .padding(.bottom, 30)
            }
            // Without permission for reminders, the taps come from the screen while it is up.
            .sensoryFeedback(.success, trigger: clock?.isAdapted(at: now) ?? false) { old, new in !old && new && permission != .authorized }
            .modifier(MilestoneTap(park: park, next: next, active: true))
        }
    }
    @ViewBuilder private var control: some View {
        if store.adaptation != nil {
            Button(role: .destructive) { store.stopAdaptation() } label: { Label("Stop", systemImage: "stop.fill") }
                .tint(palette.toolbarTint)
                .accessibilityHint("Resets the clock and cancels the reminders.")
        } else {
            Button { start() } label: { Label("Start", systemImage: "play.fill") }
                .tint(palette.toolbarTint)
                .handGestureShortcut(.primaryAction)
                .accessibilityHint("Starts a 30-minute dark-adaptation clock.")
        }
    }
    private func start() {
        store.startAdaptation()
        Task {
            // The request happens in `schedule`; read the answer back for the screen's own haptic.
            try? await Task.sleep(for: .seconds(1))
            permission = await AdaptationReminders.status()
        }
    }
}

/// The next moment of the night, under the clock: what the eyes are adapting for.
private struct NextInDark: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    let next: NightMilestone
    let now: Date
    var body: some View {
        VStack(spacing: 0) {
            countdownText(next, now: now).font(.system(.subheadline, design: .serif))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.7)
            Text("at \(night.park.time(next.date))").font(.caption2).foregroundStyle(palette.muted).nonEssential()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// The adaptation clock as the gauge's arc: open at the bottom, a tick every five minutes, the
/// leading star where the minutes have reached, the minutes in the middle. The arc springs to each
/// new minute (still under Reduce Motion); wrist down it drops its glow and keeps the minutes.
struct AdaptationRing: View {
    @Environment(\.nyx) private var palette
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let clock: AdaptationClock?
    let now: Date
    @State private var shown = 0.0
    var body: some View {
        let progress = clock?.progress(at: now) ?? 0
        let minutes = clock?.elapsedMinutes(at: now) ?? 0
        let adapted = clock?.isAdapted(at: now) ?? false
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RingArc(value: shown, dimmed: dimmed, palette: palette)
                VStack(spacing: -side*0.02) {
                    Text(clock == nil ? AdaptationClock.minutes : minutes, format: .number)
                        .font(.system(size: side*0.36, weight: .light, design: .serif)).monospacedDigit()
                        .foregroundStyle(palette.accent).lineLimit(1).minimumScaleFactor(0.5)
                    Group {
                        if adapted { Text("adapted") } else if clock == nil { Text("minutes") } else { Text("of 30 min") }
                    }
                    .font(.system(size: max(10, side*0.11), design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, side*0.16).offset(y: -side*0.03)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dark adaptation")
        .accessibilityValue(clock == nil ? String(localized: "Not started") : adapted ? String(localized: "Adapted, 30 minutes") : String(localized: "\(minutes) of about 30 minutes"))
        .task(id: progress) {
            withAnimation(reduceMotion || dimmed ? nil : NyxMotion.spring) { shown = progress }
        }
    }
}

private struct RingArc: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    let dimmed: Bool
    let palette: NyxPalette
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width/2, y: size.height/2), radius = min(size.width, size.height)/2 - 10
            let start = 140.0, sweep = 260.0
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start+sweep), clockwise: false)
            context.stroke(track, with: .color(palette.line), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for tick in 0...6 {
                let a = (start + Double(tick)*sweep/6) * .pi/180
                var line = Path()
                line.move(to: CGPoint(x: center.x+cos(a)*(radius-5), y: center.y+sin(a)*(radius-5)))
                line.addLine(to: CGPoint(x: center.x+cos(a)*(radius-10), y: center.y+sin(a)*(radius-10)))
                context.stroke(line, with: .color(Double(tick)/6 <= value ? palette.accent.opacity(0.7) : palette.line), lineWidth: 1)
            }
            guard value > 0.002 else { return }
            let tip = start + sweep*min(1, value)
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(tip), clockwise: false)
            if !dimmed {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 4))
                    glow.stroke(arc, with: .color(palette.accent.opacity(0.35)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
            }
            context.stroke(arc, with: .color(palette.accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            let point = CGPoint(x: center.x+cos(tip * .pi/180)*radius, y: center.y+sin(tip * .pi/180)*radius)
            context.fill(Path(ellipseIn: CGRect(x: point.x-2.8, y: point.y-2.8, width: 5.6, height: 5.6)), with: .color(palette.ink))
        }
        .accessibilityHidden(true)
    }
}

/// Why the clock exists, in a sheet so the field screen stays one glance.
private struct AdaptationInfo: View {
    @Environment(\.nyx) private var palette
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dark adaptation").font(.system(.headline, design: .serif))
                Text("Eyes take 20 to 30 minutes to adapt to the dark. A bright screen or a white light resets them.")
                Text("Red light only. Nyx taps your wrist at 25 and 30 minutes, even with the screen off.")
                    .foregroundStyle(palette.muted)
            }
            .font(.footnote).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.ink).background(Color.black)
    }
}

/// Wrist taps at 25 and 30 minutes of dark adaptation, as local notifications so they arrive with
/// the screen off or another app up. Permission is asked the first time the clock starts.
enum AdaptationReminders {
    static let prefix = "nyx.adaptation."
    private static var identifiers: [String] { AdaptationClock.reminderMinutes.map { prefix + String($0) } }
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    static func schedule(_ clock: AdaptationClock, now: Date) {
        Task {
            let center = UNUserNotificationCenter.current()
            var status = await status()
            if status == .notDetermined {
                status = (try? await center.requestAuthorization(options: [.alert, .sound])) == true ? .authorized : .denied
            }
            // Stopped while the question was up: nothing to remind.
            guard status == .authorized || status == .provisional, WatchSky.adaptationStart == clock.start else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            for reminder in clock.reminders(after: .now) {
                let content = UNMutableNotificationContent()
                if reminder.minutes < AdaptationClock.minutes {
                    content.title = String(localized: "Nearly adapted")
                    content.body = String(localized: "Five more minutes for full dark adaptation. Keep the screen red.")
                } else {
                    content.title = String(localized: "Eyes adapted")
                    content.body = String(localized: "Your eyes have adapted. Keep the screen red.")
                }
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: prefix + String(reminder.minutes), content: content, trigger: trigger))
            }
        }
    }
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// With Nyx on screen a reminder is a tap and a line in Notification Center, never a bright
/// banner over the red screen: the ring already shows it.
nonisolated final class AdaptationNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = AdaptationNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.sound, .list]
    }
}

#Preview("Not started") {
    WatchPreviewHost(nightVision: true) { park, _ in DarkAdaptationView(park: park) }
}
#Preview("Ring • 12 min") {
    AdaptationRing(clock: AdaptationClock(start: .now.addingTimeInterval(-12*60)), now: .now)
        .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true)).padding()
}
#Preview("Ring • adapted • Always-On") {
    AdaptationRing(clock: AdaptationClock(start: .now.addingTimeInterval(-40*60)), now: .now)
        .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true))
        .environment(\.isLuminanceReduced, true).padding()
}
