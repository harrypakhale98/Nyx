import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// MARK: Dark weekends

/// The long view for one place: around each of the next six new moons, the weekend (a Friday and
/// the Saturday after it) whose better night scores highest. Far ahead a score rests on the
/// place's usual clouds for the month and says so (`Night.basisLabels`); the Moon and the hours of
/// true darkness are exact. For deciding which weekends to ask off and book, months ahead.
nonisolated enum DarkWeekends {
    struct Weekend: Sendable, Identifiable {
        var id: Date { friday.id }
        let newMoon: Date
        let friday: Night
        let saturday: Night
        /// The weekend's better night, the one the row leads with.
        var best: Night { NightPlanner.better(saturday,friday) ? saturday : friday }
    }
    static let lunations=6
    /// A weekend counts for a new moon when its Friday falls within this many days either side.
    static let reach=4
    /// The next `count` new moons from `now`.
    static func newMoons(after now: Date, count: Int=lunations) -> [Date] {
        var moons: [Date]=[], from=now
        for _ in 0..<count { let next=MoonWeek.newMoon(after:from); moons.append(next); from=next.addingTimeInterval(86400) }
        return moons
    }
    /// The Fridays (as the park's evenings) within `reach` days of a new moon.
    static func fridays(around newMoon: Date, park: Park) -> [Date] {
        let evening=park.evening(newMoon)
        return (-reach...reach).map { park.date(evening,addingDays:$0) }.filter { park.calendar.component(.weekday,from:$0)==6 }
    }
    /// The best weekend around each new moon still ahead. `night` scores a park's evening as every
    /// screen does; `closure` counts against a night as wherever a best night is chosen.
    static func plan(park: Park, newMoons: [Date], tonight: Date, closure: String?, night: (Date) -> Night) -> [Weekend] {
        let closures=closure.map { [park.id:$0] } ?? [:]
        return newMoons.compactMap { moon in
            let weekends=fridays(around:moon,park:park).filter { $0>=tonight }.map { friday in
                Weekend(newMoon:moon,friday:night(friday),saturday:night(park.date(friday,addingDays:1)))
            }
            return weekends.min { NightPlanner.better($0.best,$1.best,closures:closures) }
        }
    }
    /// "New moon Mar 11" in the place's calendar.
    static func newMoonLine(_ weekend: Weekend) -> String {
        var format=Date.FormatStyle.dateTime.month(.abbreviated).day(); format.timeZone=weekend.friday.park.timeZone
        return String(localized:"New moon \(weekend.newMoon.formatted(format))")
    }
    /// What VoiceOver hears for a row.
    static func spoken(_ weekend: Weekend) -> String {
        let park=weekend.friday.park
        return Sentences.join([String(localized:"\(park.dayLabel(weekend.friday.id)) and \(park.dayLabel(weekend.saturday.id)): \(weekend.friday.score.value) and \(weekend.saturday.score.value)."),
                               Sentences.end(newMoonLine(weekend))]+weekend.best.basisLabels.map(Sentences.end))
    }
}

// MARK: Milky Way season

/// When the Milky Way's bright core is up at least an hour in true darkness, by geometry alone (the
/// Moon is left out: its nights are the weekends'). Found by stepping through the coming year,
/// three days at a time, then day by day at the edges. Nil where the core never climbs high enough.
nonisolated struct CoreSeason: Sendable, Equatable {
    let start: Date
    let end: Date
    /// True when today is inside the season.
    let now: Bool
    static let minimum: TimeInterval=3600
    static func find(park: Park, from today: Date, days: Int=366, engine: AstronomyEngine=AstronomyEngine(), almanac: SkyAlmanac=SkyAlmanac()) -> CoreSeason? {
        let first=park.evening(today)
        func up(_ offset: Int) -> Bool {
            let sky=engine.conditions(for:park,on:park.date(first,addingDays:offset))
            guard sky.darkHours>0 else { return false }
            return (almanac.core(for:park,sky:sky).dark?.duration ?? 0)>=minimum
        }
        // Coarse pass, then the exact days either side of each change.
        let marks=Array(stride(from:0,to:days,by:3)).map { ($0,up($0)) }
        guard let on=marks.firstIndex(where:\.1) else { return nil }
        func edge(after a: Int, before b: Int, wanted: Bool) -> Int { (a+1...b).first { up($0)==wanted } ?? b }
        let startDay=on==0 ? 0 : edge(after:marks[on-1].0,before:marks[on].0,wanted:true)
        let off=marks[on...].firstIndex { !$0.1 }
        let endDay=off.map { edge(after:marks[$0-1].0,before:marks[$0].0,wanted:false)-1 } ?? (days-1)
        return CoreSeason(start:park.date(first,addingDays:startDay),end:park.date(first,addingDays:endDay),now:startDay==0)
    }
    /// "Milky Way season at Joshua Tree runs until about Oct 12." or "…opens about Feb 20 and runs to about Oct 12."
    func sentence(_ park: Park) -> String {
        var format=Date.FormatStyle.dateTime.month(.abbreviated).day(); format.timeZone=park.timeZone
        let from=start.formatted(format), to=end.formatted(format)
        return now ? String(localized:"Milky Way season at \(park.shortName) runs until about \(to): the core is up at least an hour in true darkness on moonless nights.")
                   : String(localized:"Milky Way season at \(park.shortName) opens about \(from) and runs to about \(to): the core is up at least an hour in true darkness on moonless nights.")
    }
}

// MARK: Into a calendar

/// The weekends' nights as one calendar file (iCalendar, `.ics`) the person shares to their
/// calendar app: one event per night, from true darkness to its end, with the score and what it
/// rests on. Built on this device; nothing is sent, and no calendar is read.
nonisolated struct DarkNightsCalendar: Transferable {
    let park: Park
    let nights: [Night]
    var closure: String?=nil
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType:.calendarEvent) { file in
            let url=FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try Data(file.text().utf8).write(to:url,options:.atomic)
            return SentTransferredFile(url)
        }
    }
    var fileName: String { "Nyx \(park.shortName).ics".replacingOccurrences(of:"/",with:"-") }
    /// "20270313T034500Z": a moment in UTC, as the file's times are written.
    static func stamp(_ date: Date) -> String {
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone = .gmt
        let c=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:date)
        return String(format:"%04d%02d%02dT%02d%02d%02dZ",c.year ?? 0,c.month ?? 0,c.day ?? 0,c.hour ?? 0,c.minute ?? 0,c.second ?? 0)
    }
    /// Text escaped as iCalendar asks: backslash, semicolon, comma and line breaks.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:";",with:"\\;").replacingOccurrences(of:",",with:"\\,").replacingOccurrences(of:"\n",with:"\\n")
    }
    /// Lines longer than 75 bytes folded onto continuation lines, as the format asks.
    static func fold(_ line: String) -> String {
        var out: [String]=[], current=""
        for character in line {
            if (current+String(character)).utf8.count>(out.isEmpty ? 75 : 74) { out.append(current); current="" }
            current.append(character)
        }
        out.append(current)
        return out.joined(separator:"\r\n ")
    }
    /// Each night as the single "Add to Calendar" event reads (`CalendarDraft`): its title, hours and notes.
    func text(now: Date = .now) -> String {
        var lines=["BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//Nyx//Dark nights//EN","CALSCALE:GREGORIAN"]
        for night in nights {
            let draft=CalendarDraft(night:night,closure:closure)
            lines+=["BEGIN:VEVENT","UID:nyx-\(park.id)-\(park.isoDay(night.id))","DTSTAMP:\(Self.stamp(now))","DTSTART:\(Self.stamp(draft.start))","DTEND:\(Self.stamp(draft.end))",
                    "SUMMARY:"+Self.escape(draft.title),"LOCATION:"+Self.escape(draft.location),"DESCRIPTION:"+Self.escape(draft.notes)]
            if let url=draft.url { lines.append("URL:"+url.absoluteString) }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(Self.fold).joined(separator:"\r\n")+"\r\n"
    }
}
