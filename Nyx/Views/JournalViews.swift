import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct JournalView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Query(sort:\JournalEntry.date,order:.reverse) private var entries:[JournalEntry]
    @MotionReduced private var reduceMotion: Bool
    @State private var editing=false
    @State private var deleting:JournalEntry?
    @State private var saveError=false
    @State private var opened:JournalEntry?
    @State private var recap=false
    @State private var width=0.0
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var exporting:JournalDocument?
    @State private var staged:URL?
    @State private var importing=false
    @State private var importResult:String?
    @State private var exportFailed=false
    /// A journal's manifest read and checked, waiting for the person to confirm the import. Its
    /// photos stay in the file until the merge reads them.
    @State private var pendingImport:PendingImport?
    /// An export being gathered or an import being read, off the main thread (photos can be many megabytes).
    @State private var working:LocalizedStringKey?
    /// A park dropped onto the journal (a new entry for it, tonight's date), or a night from Plan's month.
    @State private var dropped:JournalPrefill?
    /// A wide iPad: your constellation large on the left, the nights themselves on the right.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    var body:some View {
        let nights=model.loggedNights(entries)
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                if model.journalUnavailable { JournalUnavailableBanner(needsSpace:model.journalNeedsSpace) }
                // One way into the year: at the top in recap season (December, early January), else under the constellation.
                let season=recapSeason(nights)
                if season { recapCard() }
                if wide && !entries.isEmpty {
                    // The two columns meet at iPhone Duo's fold on its inner display, half open or flat.
                    FoldColumns(narrow:.trailing,narrowMax:min(440,(width*0.4).rounded()),spacing:NyxMetrics.columnGap) {
                        YourSkyPanel(nights:nights) { id in opened=entries.first { $0.id==id } }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:24) { if !season && !nights.isEmpty { recapCard(rule:false) }; entryList }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                } else if wide {
                    // No nights yet: the constellation alone, centred, with its promise and the button inside.
                    YourSkyPanel(nights:nights,record:recordAction) { _ in }.frame(maxWidth:760).frame(maxWidth:.infinity)
                } else {
                    YourSkyPanel(nights:nights,record:recordAction) { id in opened=entries.first { $0.id==id } }
                    if !season && !nights.isEmpty { recapCard() }
                    entryList
                }
            }.padding(NyxMetrics.pagePadding).readableColumn(wide ? WideLayout.twoColumnMaximum : WideLayout.readableWidth)
        }.measuringWidth($width).foldSource().background(NightBackground()).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            .tabRootToolbar()
            .toolbar {
                // Nothing is recorded into a journal that could not be opened: it would be lost. Dimmed by hand, since
                // the app's ink foreground style (`RootView`) holds bar symbols at full strength when disabled.
                // Recording a night is the Journal's everyday action, so on iPhone Duo's side bar it overflows last.
                if #available(iOS 27.0,*) {
                    ToolbarItem(placement:.topBarTrailing) { recordButton }.visibilityPriority(.high)
                } else {
                    ToolbarItem(placement:.topBarTrailing) { recordButton }
                }
                // Export and import are rare: on iOS 27 they live in the system's own overflow menu (the
                // ellipsis is reserved for it, always last), on iOS 26 in a menu of their own, also last.
                if #available(iOS 27.0,*) {
                    ToolbarOverflowMenu { journalFileActions }
                } else {
                    ToolbarItem(placement:.topBarTrailing) { Menu { journalFileActions } label:{ Label { Text("Journal options") } icon:{ Image(systemName:"ellipsis").opacity(model.journalUnavailable ? 0.35 : 1) } }.accessibilityLabel("Journal options").disabled(model.journalUnavailable) }
                }
            }
            .navigationDestination(item:$opened) { entry in JournalDetailView(entry:entry) }
            .navigationDestination(isPresented:$recap) { YearRecapView(nights:nights) }
            .sheet(isPresented:$editing) { NavigationStack { JournalEditorView() }.nyxPresentation() }
            .sheet(item:$dropped) { prefill in NavigationStack { JournalEditorView(prefill:prefill) }.nyxPresentation() }
            // iPad: drop a park, or a night from Plan's month (held over the Journal's tab, it opens),
            // here to start an entry for it (never into a journal that could not open).
            .acceptsJournalDrop("Record a night at this park",systemImage:"book.closed") { drop in record(drop) }
            .confirmationDialog("Delete this night?",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting=nil }}),titleVisibility:.visible) { Button("Delete entry",role:.destructive) { if let deleting { context.delete(deleting);do { try context.save() } catch { context.rollback();saveError=true } };deleting=nil } }
            .alert("Unable to delete",isPresented:$saveError) { Button("OK",role:.cancel) {} } message:{ Text("The entry is still here. Try again when space is available.") }
            // The package gathered on disk is cleared once the exporter has copied it, or was cancelled.
            .fileExporter(isPresented:Binding(get:{ exporting != nil },set:{ if !$0 { exporting=nil } }),document:exporting,contentTypes:[.nyxJournal],
                          defaultFilename:String(localized:"Nyx Journal \(Date.now.formatted(Date.ISO8601FormatStyle(timeZone:.current).year().month().day()))")) { result in
                let done=staged;staged=nil
                Task.detached(priority:.utility) { JournalExport.clear(done) }
                if case .failure=result { exportFailed=true }
            } onCancellation:{ let done=staged;staged=nil;Task.detached(priority:.utility) { JournalExport.clear(done) } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.nyxJournal]) { result in
                if case .success(let url)=result { Task { await importJournal(url) } }
            }
            .overlay { if let working { WorkingNote(title:working) } }
            .alert("Journal import",isPresented:Binding(get:{ importResult != nil },set:{ if !$0 { importResult=nil } })) { Button("OK",role:.cancel) {} } message:{ Text(importResult ?? "") }
            .alert("Journal export",isPresented:$exportFailed) { Button("OK",role:.cancel) {} } message:{ Text("The journal could not be exported. Try again when space is available.") }
            // Nothing is merged until the person has seen what the file holds.
            .alert("Import this journal?",isPresented:Binding(get:{ pendingImport != nil },set:{ if !$0 { pendingImport=nil } }),presenting:pendingImport) { pending in
                Button("Import") { Task { await confirmImport(pending) } }
                Button("Cancel",role:.cancel) { finishImport(pending.url) }
            } message:{ pending in Text(Self.importMessage(pending.summary)) }
            .task(id:model.journalFile) {
                // A journal opened from Files or another app.
                guard let url=model.journalFile else { return }
                model.importingJournal=url
                model.journalFile=nil
                guard !model.journalUnavailable else {
                    model.importingJournal=nil
                    Task.detached(priority:.utility) { JournalInbox.remove(url) }
                    importResult=String(localized:"Your journal could not be opened, so this file was not imported. Nothing was changed.")
                    return
                }
                await importJournal(url)
            }
    }
    /// Opens "Record a night" for a dropped night or park; false when there is nothing to record.
    private func record(_ drop:JournalDrop)->Bool {
        guard !model.journalUnavailable, editing == false, dropped == nil, let prefill=drop.prefill(model:model) else { return false }
        dropped=prefill
        return true
    }
    /// Writes every entry and its photos to a package on disk off the main thread, a few nights'
    /// photos at a time (`JournalArchive.write`), so a long journal is never in memory whole; the
    /// exporter opens once the package is ready and copies it from there.
    private func exportJournal() {
        let container=context.container
        working="Preparing your journal"
        Task {
            let package=await Task.detached(priority:.userInitiated) { try? JournalExport.stage(container) }.value
            working=nil
            if let package { staged=package;exporting=JournalDocument(package:package) } else { exportFailed=true }
        }
    }
    /// Reads the package's manifest off the main thread (every count and file size checked, no
    /// photo opened), then asks before anything is merged: the counts, and that spots arrive
    /// unfollowed. The file stays where it is until the import is confirmed or cancelled; a copy
    /// another app left in Documents/Inbox is removed then, or at once when it cannot be read.
    private func importJournal(_ url:URL) async {
        working="Importing your journal"
        model.importingJournal=url
        let read=await Task.detached(priority:.userInitiated) { () -> Result<JournalImport,any Error> in Result { try JournalImport.read(url) } }.value
        working=nil
        switch read {
        case .success(let prepared):
            if let summary=try? prepared.summary(in:context) { pendingImport=PendingImport(prepared:prepared,summary:summary,url:url); return }
            importResult=String(localized:"This file could not be read as a Nyx journal. Nothing was changed.")
        case .failure(let error):
            importResult=(error as? JournalArchive.ArchiveError) == .tooLarge ? Self.tooLargeMessage
                : String(localized:"This file could not be read as a Nyx journal. Nothing was changed.")
        }
        finishImport(url)
    }
    /// Adds the nights the journal does not have yet; nothing already here is changed. The photos
    /// are read and re-encoded a few nights at a time off the main thread (`JournalImport.merge`),
    /// in a context of the merge's own, and one save makes it all or nothing.
    private func confirmImport(_ pending:PendingImport) async {
        working="Importing your journal"
        defer { working=nil; finishImport(pending.url) }
        do {
            let result=try await pending.prepared.merge(into:context,batch:JournalImport.mergeBatch)
            importResult=result.skipped==0 ? String(localized:"Nights added: \(result.added).") : String(localized:"Nights added: \(result.added). Already in your journal: \(result.skipped).")
        } catch {
            importResult=String(localized:"This file could not be read as a Nyx journal. Nothing was changed.")
        }
    }
    /// The import of `url` is over (merged, cancelled or unreadable): the file is no longer kept
    /// from the Inbox sweep, and a copy another app left there is removed.
    private func finishImport(_ url:URL) {
        if model.importingJournal == url { model.importingJournal=nil }
        Task.detached(priority:.utility) { JournalInbox.remove(url) }
    }
    /// The confirmation's words: what the file holds, what is skipped, and how spots arrive.
    nonisolated static func importMessage(_ summary:JournalImport.Summary)->String {
        var lines=[summary.spots>0 ? String(localized:"Nights: \(summary.nights). Photos: \(summary.photos). Spots: \(summary.spots).")
                                   : String(localized:"Nights: \(summary.nights). Photos: \(summary.photos).")]
        if summary.alreadyHere>0 { lines.append(String(localized:"Already in your journal, so skipped: \(summary.alreadyHere).")) }
        if summary.spots>0 { lines.append(String(localized:"Spots arrive in Your spots without reminders. Open one and add it to widgets and reminders.")) }
        return lines.joined(separator:"\n")
    }
    /// A journal past `JournalImport`'s limits, with the limits in the reader's own numbers.
    nonisolated static var tooLargeMessage:String {
        let nights=JournalImport.maxEntries.formatted(), size=Int64(PhotoScaling.maxSourceBytes).formatted(.byteCount(style:.file))
        return String(localized:"This journal is too large to import. Nyx imports up to \(nights) nights, \(PhotoScaling.perEntry) photos a night and \(size) a photo. Nothing was changed.")
    }
    @ViewBuilder private var entryList: some View {
        // An empty journal's button sits inside the constellation, under its promise (`YourSkyPanel`).
        if !entries.isEmpty {
            LazyVStack(spacing:24) { ForEach(entries) { entry in NavigationLink { JournalDetailView(entry:entry) } label:{ JournalCard(entry:entry) }.buttonStyle(.plain).hoverEffect(.lift).contextMenu { Button("Delete entry",role:.destructive) { deleting=entry } }
                .transition(reduceMotion ? AnyTransition.opacity : .opacity.combined(with:.scale(scale:0.96))) }
            }
            // A night recorded or deleted settles into the list instead of jumping it (at once under Reduce Motion).
            .animation(reduceMotion ? nil : NyxMotion.spring,value:entries.map(\.persistentModelID))
        }
    }
    /// The empty constellation's "Record a night", never into a journal that could not open.
    /// Export and import, in the system overflow menu (iOS 27) or the Journal's own (iOS 26).
    /// Export and import, under the one thing to know about them on every device, said once: a journal
    /// lives on the device it was written on.
    @ViewBuilder private var journalFileActions: some View {
        Section("Journals stay on each device. Export to move yours.") {
            Button("Export journal",systemImage:"square.and.arrow.up") { exportJournal() }
                .disabled(entries.isEmpty || model.journalUnavailable || working != nil)
            Button("Import journal",systemImage:"square.and.arrow.down") { importing=true }.disabled(model.journalUnavailable || working != nil)
        }
    }
    private var recordButton: some View {
        Button { editing=true } label:{ Label { Text("Record a night") } icon:{ Image(systemName:"plus").opacity(model.journalUnavailable ? 0.35 : 1) } }
            .disabled(model.journalUnavailable)
    }
    private var recordAction: (()->Void)? { entries.isEmpty && !model.journalUnavailable ? { editing=true } : nil }
    /// December (and the first days of January): the year's recap waits at the top of the journal.
    private func recapSeason(_ nights:[LoggedNight])->Bool {
        // Gregorian months and years, whatever calendar the device uses; each night's year where it was spent.
        let now=model.today, calendar=JournalYear.calendar(.current)
        let month=calendar.component(.month,from:now), year=calendar.component(.year,from:now)
        let recapYear=month==12 ? year : month==1 && calendar.component(.day,from:now)<=7 ? year-1 : nil
        return recapYear.map { y in nights.contains { $0.year==y } } ?? false
    }
    /// `rule` off where it opens a column, level with the other column's first section.
    private func recapCard(rule:Bool=true)->some View {
        Button { recap=true } label:{
            Panel(rule:rule) { HStack(spacing:14) {
                // A label, as the skies count above it is, so the two rows' icons and words line up.
                Label { VStack(alignment:.leading,spacing:4) {
                    Text("Your year under the stars").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    // Written on this iPhone when the system model is available; Nyx's own words otherwise.
                    Text(OnDeviceGuide.speaksYourLanguage ? "Nights out, your darkest sky, the moons you met, and a few words on the season, written on this iPhone." : "Nights out, your darkest sky, and the moons you met.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                } } icon:{ Image(systemName:"sparkles").foregroundStyle(palette.ink).accessibilityHidden(true) }
                Spacer(minLength:0)
                Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
            } }
        }.buttonStyle(.plain).accessibilityElement(children:.combine).accessibilityAddTraits(.isButton)
    }
}
/// A stock spinner on a solid panel while the journal is exported or imported; solid, not glass,
/// so it reads over the sky in night vision and with Reduce Transparency alike.
private struct WorkingNote: View {
    @Environment(\.nyx) private var palette
    let title:LocalizedStringKey
    var body: some View {
        ProgressView { Text(title) }.tint(palette.ink).foregroundStyle(palette.ink)
            .padding(.vertical,18).padding(.horizontal,24)
            .nyxCard(radius:NyxMetrics.rowRadius,fill:palette.nightVision ? Color.black : palette.panel)
            .accessibilityElement(children:.combine)
    }
}
#Preview("Working note") { ZStack { Color.black; WorkingNote(title:"Preparing your journal") }.preferredColorScheme(.dark) }
/// A remembered night, with the Moon as it actually was over that park.
struct JournalCard:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    let entry:JournalEntry
    var body:some View {
        let park=model.park(entry.parkID)
        let moon=park.map { model.night($0,on:entry.date).sky.moon }
        Panel { VStack(alignment:.leading,spacing:10) {
            if let thumbnail=entry.thumbnail { JournalThumbnail(data:thumbnail).padding(.bottom,4) }
            HStack(alignment:.top,spacing:12) {
                VStack(alignment:.leading,spacing:4) {
                    Text(park?.shortName ?? String(localized:"A night outside")).font(.system(.title2,design:.serif))
                    Text(park?.dateLabel(entry.date) ?? entry.date.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(palette.muted)
                }
                Spacer(minLength:0)
                if let moon { MoonDisc(illumination:moon.illumination,waxing:moon.waxing,southern:(park?.latitude ?? 0)<0).frame(width:30,height:30).accessibilityHidden(true) }
            }
            if !entry.notes.isEmpty { Text(entry.notes).font(.subheadline).lineLimit(3).foregroundStyle(palette.ink.opacity(0.86)) }
            Text(moon.map { String(localized:"Bortle \(entry.observedBortle) observed · \($0.name), \($0.litText)") } ?? String(localized:"Observed Bortle class \(entry.observedBortle)"))
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        } }
    }
}
/// A journal's manifest read and checked (its photos not yet opened), what the confirmation says
/// about it, and the file it came from.
struct PendingImport {
    let prepared:JournalImport
    let summary:JournalImport.Summary
    let url:URL
}
/// Image I/O downsampling: decodes straight to the target size, never the full photo.
nonisolated enum PhotoScaling {
    /// The largest photo the journal accepts, from the editor, Shortcuts or an imported journal.
    static let maxSourceBytes=40_000_000
    /// The most photos one entry holds, from the editor, Shortcuts or an imported journal.
    static let perEntry=4
    /// The image types a photo may arrive as in an imported journal; anything else is left out.
    static let keepsakeTypes: Set<String>=[UTType.jpeg.identifier,UTType.heic.identifier,UTType.heif.identifier,UTType.png.identifier]
    /// A photo from outside the editor as the journal keeps it: a JPEG, HEIC or PNG drawn again as
    /// the editor's JPEG (at most 2,400 pixels on the long edge), which carries none of the
    /// original file's metadata (location, camera, dates); nil for any other data.
    static func keepsake(_ data:Data)->Data? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil), CGImageSourceGetCount(source)>0,
              let type=CGImageSourceGetType(source) as String?, keepsakeTypes.contains(type) else { return nil }
        return jpeg(data,maxPixels:2400)
    }
    /// True when Image I/O recognizes the data as an image (read from its header; nothing is decoded).
    static func isImage(_ data:Data)->Bool {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source)>0
    }
    static func image(_ data:Data,maxPixels:Int)->CGImage? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil) else { return nil }
        let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
                                    kCGImageSourceThumbnailMaxPixelSize:maxPixels,kCGImageSourceShouldCacheImmediately:true]
        return CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary)
    }
    /// Journal photos are keepsakes, not originals: JPEG, at most `maxPixels` on the long edge.
    static func jpeg(_ data:Data,maxPixels:Int)->Data? {
        image(data,maxPixels:maxPixels).flatMap { UIImage(cgImage:$0).jpegData(compressionQuality:0.85) }
    }
}
/// A stored photo, decoded off the main thread at the size it is shown.
struct PhotoView:View {
    let data:Data
    let maxPixels:Int
    var fill=false
    @State private var image:UIImage?
    @MotionReduced private var reduceMotion: Bool
    var body:some View {
        Group {
            if let image {
                if fill { Image(uiImage:image).resizable().scaledToFill() } else { Image(uiImage:image).resizable().scaledToFit() }
            } else { Color.black.aspectRatio(fill ? 1 : 4/3,contentMode:.fit) }
        }
        .accessibilityIgnoresInvertColors()
        .task(id:data.count ^ data.prefix(64).hashValue) {
            let data=data, size=maxPixels
            let decoded=await Task.detached(priority:.utility) { PhotoScaling.image(data,maxPixels:size).map { UIImage(cgImage:$0) } }.value
            withAnimation(reduceMotion ? nil : .easeOut(duration:0.25)) { image=decoded }
        }
    }
}
/// A journal card's photo: the stored small thumbnail, so a long journal scrolls smoothly.
struct JournalThumbnail:View {
    let data:Data
    var body:some View {
        Color.black.frame(height:150).overlay { PhotoView(data:data,maxPixels:900,fill:true) }
            .clipShape(RoundedRectangle(cornerRadius:16))
            .accessibilityHidden(true)
    }
}
@MainActor @Observable final class JournalEditorModel {
    var date=Date.now { didSet { if oldValue != date, settled { dateChosen=true } } }
    /// The person picked a date, so appearing again never replaces it.
    private(set) var dateChosen=false
    @ObservationIgnored private var settled=false
    var parkID=Park.defaultID
    var observedBortle=3
    var notes=""
    var photos:[Data]=[] { didSet { descriptions=Self.aligned(descriptions,to:photos.count) } }
    /// Each photo's description for VoiceOver, in the same order; "" for none.
    var descriptions:[String]=[]
    /// A description the on-device model suggested, per photo, until the person uses or dismisses it.
    var suggestions:[Int:String]=[:]
    var suggesting:Set<Int>=[]
    /// Photos the last request found nothing to suggest for, so the person hears why the button did nothing.
    var unsuggested:Set<Int>=[]
    var loadingPhotos=false
    /// A save under way (its thumbnail being scaled), so Save cannot store the night twice.
    var saving=false
    var error:String?
    var saved=false
    /// What the editor holds, to tell an untouched form from one with words or photos in it.
    private struct Draft:Equatable {
        let date:Date, parkID:String, observedBortle:Int, notes:String, photos:[Data], descriptions:[String]
    }
    private var draft:Draft { Draft(date:date,parkID:parkID,observedBortle:observedBortle,notes:notes,photos:photos,descriptions:descriptions) }
    @ObservationIgnored private var clean:Draft?
    /// Something was written, chosen or added since the editor opened (or was prefilled): closing
    /// it asks first, and a swipe down cannot throw it away.
    var hasChanges:Bool { !saved && clean.map { $0 != draft } ?? false }
    /// The form as it stands is the starting point: after opening, prefilling, or the date moving to the night just seen.
    func markClean() { clean=draft }
    /// A new entry's words, kept on this device whenever Nyx leaves the screen with the editor open, so
    /// iOS closing Nyx in the background (often, at night, while photos are taken) loses nothing: the
    /// next new entry opens with them. Photos are not kept; they are still in the photo library.
    private struct KeptDraft:Codable { var date:Date; var parkID:String; var observedBortle:Int; var notes:String; var kept:Date }
    private static let keptKey="journalDraft"
    /// This editor opened with words kept from an earlier one.
    private(set) var restored=false
    func keep() {
        guard let data=try? JSONEncoder().encode(KeptDraft(date:date,parkID:parkID,observedBortle:observedBortle,notes:notes,kept:.now)) else { return }
        UserDefaults.standard.set(data,forKey:Self.keptKey)
    }
    static func forgetKept() { UserDefaults.standard.removeObject(forKey:keptKey) }
    init(entry:JournalEntry?=nil,restoring:Bool=true) {
        defer { settled=true; clean=restored ? Draft(date:date,parkID:parkID,observedBortle:observedBortle,notes:"",photos:[],descriptions:[]) : draft }
        if let entry { date=entry.date;parkID=entry.parkID;observedBortle=entry.observedBortle;notes=entry.notes;photos=entry.photos;descriptions=entry.orderedPhotos.map { $0.altText ?? "" } }
        else if restoring, DebugScenario.screen == nil, let data=UserDefaults.standard.data(forKey:Self.keptKey),
                let kept=try? JSONDecoder().decode(KeptDraft.self,from:data), kept.kept.timeIntervalSinceNow > -2*86_400, !kept.notes.isEmpty {
            date=min(kept.date,.now);parkID=kept.parkID;observedBortle=kept.observedBortle;notes=kept.notes;restored=true
        }
        else if let home=UserDefaults.standard.string(forKey:"homePark") { parkID=home }
        #if DEBUG
        if DebugScenario.state=="error" { error=String(localized:"This night could not be stored. Try again when space is available.") }
        if DebugScenario.state=="photo",let image=UIImage(named:"LaunchStars")?.pngData() { photos=[image] }
        if DebugScenario.isEnabled("suggest-fixture"), !photos.isEmpty { suggestions[0]="A dark ridge under a sky full of stars, with a faint band of light above it." }
        #endif
        // Observers do not run inside init: one description per photo from the start.
        descriptions=Self.aligned(descriptions,to:photos.count)
    }
    /// Adds the photos picked. An empty pick (the picker cleared after a load) changes nothing, so
    /// the last load's message stays on screen.
    func load(_ items:[PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loadingPhotos=true;error=nil;defer { loadingPhotos=false }
        for item in items.prefix(max(0,PhotoScaling.perEntry-photos.count)) {
            do {
                if let data=try await item.loadTransferable(type:Data.self), data.count<=PhotoScaling.maxSourceBytes {
                    // Decode and shrink off the main thread: a 48 MP photo is hundreds of megabytes decoded. Only the
                    // re-encoded JPEG is kept, never the original file and its metadata (location, camera, dates).
                    if let kept=await Task.detached(priority:.userInitiated,operation:{ PhotoScaling.jpeg(data,maxPixels:2400) }).value { photos.append(kept) }
                    else { error=String(localized:"The photo could not be loaded. Try choosing it again.") }
                }
                else { error=String(localized:"This photo is too large. Choose a smaller image.") }
            } catch { self.error=String(localized:"The photo could not be loaded. Try choosing it again.") }
        }
    }
    /// `values` padded with "" or cut to `count`.
    nonisolated static func aligned(_ values:[String],to count:Int)->[String] { Array((values+Array(repeating:"",count:max(0,count-values.count))).prefix(count)) }
    func removePhoto(at index:Int) {
        guard photos.indices.contains(index) else { return }
        descriptions.remove(at:index)
        photos.remove(at:index)
        suggestions=Dictionary(uniqueKeysWithValues:suggestions.compactMap { $0.key<index ? ($0.key,$0.value) : $0.key>index ? ($0.key-1,$0.value) : nil })
        unsuggested=Set(unsuggested.compactMap { $0<index ? $0 : $0>index ? $0-1 : nil })
    }
    /// Asks the on-device model for a draft; it waits beside the field until used or dismissed.
    func suggest(_ index:Int) async {
        guard photos.indices.contains(index), !suggesting.contains(index) else { return }
        suggesting.insert(index); defer { suggesting.remove(index) }
        let data=photos[index]
        unsuggested.remove(index)
        let line=await PhotoDescriber.suggest(data)
        guard photos.indices.contains(index), photos[index]==data else { return }
        if let line { suggestions[index]=line }
        else {
            unsuggested.insert(index)
            AccessibilityNotification.Announcement(String(localized:"Nothing to suggest for this photo. Describe it in your own words.")).post()
        }
    }
    func useSuggestion(_ index:Int) {
        guard let line=suggestions[index], descriptions.indices.contains(index) else { return }
        descriptions[index]=line; suggestions[index]=nil
    }
    /// Stores the night. The card's thumbnail is scaled off the main thread first.
    func save(context:ModelContext,existing:JournalEntry?) async -> Bool {
        // A second tap on Save, before the first has finished, stores nothing (it stored the night twice).
        guard !saving, !saved else { return false }
        error=nil
        saving=true; defer { saving=false }
        let first=photos.first
        let thumbnail=await Task.detached(priority:.userInitiated) { first.flatMap { PhotoScaling.jpeg($0,maxPixels:900) } }.value
        let entry=existing ?? JournalEntry(date:date,parkID:parkID)
        entry.date=date;entry.parkID=parkID;entry.observedBortle=observedBortle;entry.notes=notes;entry.photos=photos
        // Only what the person wrote or chose to use is kept; a suggestion never saves itself.
        for (photo,text) in zip(entry.orderedPhotos,Self.aligned(descriptions,to:photos.count)) {
            let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
            photo.altText=trimmed.isEmpty ? nil : trimmed
        }
        entry.thumbnail=thumbnail
        if existing==nil { context.insert(entry) }
        do { try context.save();saved=true;if existing == nil { Self.forgetKept() };return true } catch { context.rollback();self.error=String(localized:"This night could not be stored. Try again when space is available.");return false }
    }
}
struct JournalEditorView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// An iPhone in landscape, where the keyboard leaves about a hundred points of form.
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    @FocusState private var writingNotes:Bool
    /// The Bortle row's width and its label's widest word: where that word would not fit beside the
    /// stepper (about 104 pt with its gap), the label goes above it rather than being hyphenated.
    @State private var bortleRow=0.0
    @State private var bortleWord=0.0
    @State private var editor:JournalEditorModel
    @State private var picker:[PhotosPickerItem]=[]
    /// Cancel with words or photos in the form: "Discard this night?" first.
    @State private var confirmDiscard=false
    var existing:JournalEntry?
    /// Called once the entry is saved (a kept night tells the rating request).
    var saved:(()->Void)?=nil
    private static let notesID="notes"
    private static let errorID="error"
    /// The stepper's fill: a neutral grey that keeps the white system thumb apart after night vision's red.
    private var neutral:Color { palette.nightVision ? palette.controlTint : Color(white:palette.highContrast ? 0.36 : 0.26) }
    @ViewBuilder private var bortleStepper:some View {
        let label=Text("Observed Bortle: \(editor.observedBortle)").foregroundStyle(palette.ink)
        let words=String(localized:"Observed Bortle: \(editor.observedBortle)").split(separator:" ").map(String.init)
        let stepper=Stepper(value:$editor.observedBortle,in:1...9) { label }.tint(neutral).foregroundStyle(palette.ink,palette.muted,neutral)
        Group {
            if typeSize.isAccessibilitySize && bortleWord>bortleRow-104 {
                VStack(alignment:.leading,spacing:8) { label.accessibilityHidden(true);stepper.labelsHidden() }
            } else { stepper }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ bortleRow=$0 }
        .background { ZStack { ForEach(words.indices,id:\.self) { Text(words[$0]) } }.fixedSize().hidden().onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ bortleWord=$0 } }
    }
    private var notesSection:some View {
        Section {
            // While writing, in either orientation, the field keeps a height that fits above the keyboard
            // and scrolls inside itself; on an iPhone SE in portrait a growing field put its cursor under it.
            let aboveKeyboard:CGFloat? = writingNotes ? (verticalSize == .compact ? 80 : 140) : nil
            TextEditor(text:$editor.notes).scrollContentBackground(.hidden)
                .frame(minHeight:aboveKeyboard ?? 160,maxHeight:aboveKeyboard)
                .overlay(alignment:.topLeading) {
                    if editor.notes.isEmpty { Text("What you noticed").foregroundStyle(palette.muted).padding(.top,8).padding(.leading,5).allowsHitTesting(false).accessibilityHidden(true) }
                }
                .padding(.horizontal,8).padding(.vertical,4)
                .nyxCard(radius:NyxMetrics.chipRadius,fill:palette.panel.opacity(0.5))
                .focused($writingNotes).id(Self.notesID).accessibilityLabel("Observation notes")
        } header:{ Text("Notes") }.openRows(palette)
    }
    /// Nyx leaves the screen with a new night half written: its words are kept (`JournalEditorModel.keep`).
    private func keepDraft(_ phase:ScenePhase) {
        if phase != .active, existing == nil, editor.hasChanges, !editor.notes.isEmpty { editor.keep() }
    }
    private func discard() {
        if existing == nil { JournalEditorModel.forgetKept() }
        dismiss()
    }
    /// iOS's compact date picker. Its popover stays bright under night vision (Settings says so); an
    /// inline calendar kept it red but its day numbers ignore the largest text sizes, which the audit refuses.
    private var datePicker:some View {
        DatePicker("Date",selection:$editor.date,in:...Date.now,displayedComponents:.date).environment(\.timeZone,model.park(editor.parkID)?.timeZone ?? .current)
    }
    private func showNotes(_ proxy:ScrollViewProxy) {
        guard writingNotes else { return }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo(Self.notesID,anchor:.top) }
    }
    init(existing:JournalEntry?=nil) { self.existing=existing;_editor=State(initialValue:JournalEditorModel(entry:existing)) }
    /// A new entry for a night being kept (field mode at dawn, a park's page the morning after):
    /// the park, the night it began on, the observed-Bortle default and a first line, all editable.
    init(prefill:JournalPrefill,saved:(()->Void)?=nil) {
        existing=nil; self.saved=saved
        let editor=JournalEditorModel(entry:nil,restoring:false)
        editor.parkID=prefill.parkID; editor.date=prefill.date; editor.observedBortle=prefill.observedBortle; editor.notes=prefill.notes
        editor.markClean()
        _editor=State(initialValue:editor)
    }
    var body:some View {
        @Bindable var editor=editor
        ScrollViewReader { proxy in
        Form {
            // A failed save is said where the form begins, as a caution: the form scrolls up to it and
            // VoiceOver reads it, so it is never a line of body text below the photos.
            if let error=editor.error {
                Section { Label(error,systemImage:"exclamationmark.triangle").labelStyle(.caution).fixedSize(horizontal:false,vertical:true).id(Self.errorID) }.openRows(palette)
            }
            if editor.restored {
                Section { Text("The night you were writing is back, without its photos.").font(.footnote).foregroundStyle(palette.muted) }.openRows(palette)
            }
            Section("The night") {
                datePicker
                ParkMenuRow(parkID:$editor.parkID)
                bortleStepper
                Text("Your estimate on the Bortle scale of sky brightness: 1 is the darkest sky, 9 an inner-city sky.").font(.caption).foregroundStyle(palette.muted)
            }.openRows(palette)
            // On an iPhone in landscape the keyboard leaves about a hundred points: while the notes are
            // being written they are short enough to sit whole above it and scroll within themselves, so
            // the line being written stays in sight (at 160 points it went behind the keyboard by the
            // third line). Read without the keyboard, they keep their full height, as the form scrolls.
            // A plain heading that stays once words are in, the prompt inside the field, and a hairline
            // edge around it: an open row has no card to show where the words go.
            notesSection
            Section {
                ForEach(Array(editor.photos.enumerated()),id:\.offset) { index,data in
                    PhotoDescriptionRow(editor:editor,index:index,data:data)
                }
                if editor.loadingPhotos { ProgressView("Adding photo") }
                PhotosPicker(selection:$picker,maxSelectionCount:max(0,PhotoScaling.perEntry-editor.photos.count),matching:.images) { Label("Choose photos",systemImage:"photo") }.disabled(editor.photos.count>=PhotoScaling.perEntry || editor.loadingPhotos)
            } header:{ Text("Photos") } footer:{ Text("Choose up to four photos. Nyx sees only the photos you select. They stay on this iPhone. A short description lets VoiceOver say what each one shows.").foregroundStyle(palette.muted) }
            .openRows(palette)
        }
        // The editor's controls in starlight and a neutral grey, never amber: amber is the score and light.
        .tint(palette.ink).nightForm().readableForm().defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top)
        // The notes take Return as a new line, so a drag down the form is how the keyboard goes away.
        .scrollDismissesKeyboard(.interactively)
        // In landscape, once the keyboard is up, the form shows the notes from their top edge rather than
        // only the first line above the keyboard.
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardDidShowNotification)) { _ in showNotes(proxy) }
        .onChange(of:editor.error) { _,error in
            guard let error else { return }
            withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo(Self.errorID,anchor:.top) }
            AccessibilityNotification.Announcement(error).post()
        }
        }
        .navigationTitle(existing==nil ? "Record a night" : "Edit night").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // A new entry starts on the night just seen, not the calendar day it is written on.
            if existing==nil, !editor.dateChosen, let park=model.park(editor.parkID) { editor.date=min(.now,park.lastNightBegun(at:.now)); editor.markClean() }
        }
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button(role:.cancel) { if editor.hasChanges { confirmDiscard=true } else { dismiss() } } };ToolbarItem(placement:.confirmationAction) { Button(role:.confirm) { Task { if await editor.save(context:context,existing:existing) { saved?(); dismiss() } } }.tint(palette.controlTint).accessibilityLabel("Save").accessibilityInputLabels([Text("Save"),Text("Done")]).disabled(editor.loadingPhotos || editor.saving) } }
            // A swipe down never throws away what was written; Cancel asks first.
            .interactiveDismissDisabled(editor.hasChanges)
            .onChange(of:scenePhase) { _,phase in keepDraft(phase) }
            // Kept as it is written too, so iOS ending Nyx while it is on screen loses nothing either.
            .onChange(of:editor.notes) { keepDraft(.background) }
            .confirmationDialog(existing==nil ? "Discard this night?" : "Discard your changes?",isPresented:$confirmDiscard,titleVisibility:.visible) {
                Button("Discard",role:.destructive) { discard() }
                Button("Keep editing",role:.cancel) {}
            }
            // Clearing the picker after a load changes it again; that empty pick loads nothing.
            .onChange(of:picker) { _,items in guard !items.isEmpty else { return }; Task { await editor.load(items);picker=[] } }
            .sensoryFeedback(.success,trigger:editor.saved)
    }
}
/// One photo in the editor: the picture, "Describe this photo" (read by VoiceOver as the photo's
/// label), an optional suggestion from the on-device model, and Remove.
struct PhotoDescriptionRow:View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable var editor:JournalEditorModel
    let index:Int
    let data:Data
    private var description:Binding<String> {
        Binding(get:{ editor.descriptions.indices.contains(index) ? editor.descriptions[index] : "" },set:{ if editor.descriptions.indices.contains(index) { editor.descriptions[index]=$0 } })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)) : AnyLayout(HStackLayout(alignment:.top,spacing:12))
            layout {
                // A dark photo on the void would have no edge: a panel behind it and a hairline around it.
                PhotoView(data:data,maxPixels:240,fill:true).frame(width:80,height:80)
                    .background(palette.panel).clipShape(RoundedRectangle(cornerRadius:NyxMetrics.chipRadius,style:.continuous))
                    .nyxCard(radius:NyxMetrics.chipRadius)
                    .accessibilityLabel(JournalPhotoLabel.text(description.wrappedValue,index:index))
                // Bounded and prompted as the notes are, so the two places to write look alike.
                TextField("Describe this photo",text:description,prompt:Text("Describe this photo").foregroundStyle(palette.muted),axis:.vertical).lineLimit(1...4)
                    .padding(.horizontal,10).padding(.vertical,8)
                    .nyxCard(radius:NyxMetrics.chipRadius,fill:palette.panel.opacity(0.5))
                    .accessibilityLabel("Description of photo \(index+1)")
                    .accessibilityHint("VoiceOver reads this when the photo is shown.")
            }
            if let suggestion=editor.suggestions[index] {
                VStack(alignment:.leading,spacing:8) {
                    Text("Suggested on this iPhone").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                    Text(suggestion).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:16) {
                        Button("Use this") { editor.useSuggestion(index) }.buttonStyle(.borderless).foregroundStyle(palette.ink)
                        Button("Dismiss") { editor.suggestions[index]=nil }.buttonStyle(.borderless).foregroundStyle(palette.muted)
                    }.frame(minHeight:44)
                }
                .padding(12).frame(maxWidth:.infinity,alignment:.leading)
                .nyxCard(radius:NyxMetrics.chipRadius)
                .accessibilityElement(children:.contain)
            }
            if editor.unsuggested.contains(index) {
                Text("Nothing to suggest for this photo. Describe it in your own words.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:16) { actions }
                VStack(alignment:.leading,spacing:4) { actions }
            }
        }.padding(.vertical,4)
    }
    @ViewBuilder private var actions:some View {
        if PhotoDescriber.available {
            if editor.suggesting.contains(index) { ProgressView().frame(minHeight:44).accessibilityLabel("Suggesting a description") }
            else {
                // Borderless, so only the button acts, not a tap anywhere in the row.
                Button { Task { await editor.suggest(index) } } label:{ Label("Suggest a description",systemImage:"text.below.photo").frame(minHeight:44) }
                    .buttonStyle(.borderless).foregroundStyle(palette.ink)
                    .accessibilityHint("Drafts one line on this iPhone for you to read and edit. Nothing is saved until you use it.")
            }
        }
        Button(role:.destructive) { editor.removePhoto(at:index) } label:{ Text("Remove photo").foregroundStyle(palette.muted).frame(minHeight:44).contentShape(Rectangle()) }
            .buttonStyle(.borderless).accessibilityLabel("Remove photo \(index+1)")
    }
}
/// What VoiceOver says for a journal photo: the person's description, else its place in the entry.
enum JournalPhotoLabel {
    nonisolated static func text(_ description:String?,index:Int)->String {
        let trimmed=description?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized:"Journal photo \(index+1)") : String(localized:"Photo: \(trimmed)")
    }
}
struct JournalDetailView:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry:JournalEntry
    @State private var editing=false
    @State private var confirmDelete=false
    @State private var deleteFailed=false
    /// Set before deleting, so the closing animation never reads a deleted model.
    @State private var removed=false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width=0.0
    /// A finger held on the sky's arc holds the page still, as on a park's page.
    @State private var holdingArc=false
    /// Two columns on a wide iPad (`WideLayout`); the phone's one column everywhere else.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    /// One group, so the page's spacing falls between sections and not between a title and its own lines.
    private var heading:some View {
        VStack(alignment:.leading,spacing:4) {
            Eyebrow(text:"A night remembered")
            Text(model.park(entry.parkID)?.shortName ?? String(localized:"A night outside")).font(.system(.largeTitle,design:.serif))
            Text(model.park(entry.parkID)?.dateLabel(entry.date) ?? entry.date.formatted(date:.abbreviated,time:.omitted)).font(.subheadline).foregroundStyle(palette.muted)
        }
    }
    private var notes:some View { Text(entry.notes).font(.system(.body,design:.serif)).lineSpacing(7) }
    @ViewBuilder private var photos:some View {
        ForEach(Array(entry.orderedPhotos.enumerated()),id:\.offset) { i,photo in PhotoView(data:photo.data,maxPixels:1600).clipShape(RoundedRectangle(cornerRadius:20)).accessibilityLabel(JournalPhotoLabel.text(photo.altText,index:i)) }
    }
    /// The stars as they stood over that park on that night: under the same sky, literally.
    private var entrySky:some View {
        let park=model.park(entry.parkID)
        return NightBackground(park:park,night:park.map { $0.evening(entry.date) })
    }
    /// The lit Moon as it stood over the park that night, beside what was observed.
    @ViewBuilder private var moonThatNight:some View {
        if let park=model.park(entry.parkID) {
            let night=model.night(park,on:entry.date)
            let moon=AstronomyEngine().moon(for:night)
            // VoiceOver reads the Moon once, from the line under "The Moon that night"; the disc is quiet.
            // Stacked at accessibility sizes, so the words keep the width instead of wrapping beside the disc.
            let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout(spacing:18))
            layout {
                MoonView(geometry:moon.geometry).frame(width:64,height:64).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text("The Moon that night").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                    Text("\(night.sky.moon.name), \(night.sky.moon.litText)").font(.system(.title3,design:.serif))
                    Text("Observed Bortle class \(entry.observedBortle)").font(.subheadline).foregroundStyle(palette.muted)
                }
            }
        } else { Text("Observed Bortle class \(entry.observedBortle)").font(.subheadline).foregroundStyle(palette.muted) }
    }
    var body:some View {
        ScrollView { if !removed {
            if wide {
                // A wide iPad: the words on the left at a reading measure, and beside them what the night
                // looked like, the Moon, the sky's arc and the photos, instead of one column with half the page empty.
                HStack(alignment:.top,spacing:NyxMetrics.columnGap) {
                    VStack(alignment:.leading,spacing:24) { heading;Divider().overlay(palette.line);notes;Divider().overlay(palette.line);GlobeAtNightLink() }.frame(maxWidth:.infinity,alignment:.leading)
                    VStack(alignment:.leading,spacing:24) {
                        moonThatNight
                        if let park=model.park(entry.parkID) { SkyArc(night:model.night(park,on:entry.date),isTonight:false) }
                        photos
                    }.frame(width:WideLayout.leadingWidth(width)).padding(.top,8)
                }.padding(24).readableColumn(WideLayout.twoColumnMaximum)
            } else {
                VStack(alignment:.leading,spacing:24) { heading;moonThatNight;Divider().overlay(palette.line);notes;photos;Divider().overlay(palette.line);GlobeAtNightLink() }.padding(24).readableColumn(WideLayout.proseWidth)
            }
        } }.measuringWidth($width).scrollDisabled(holdingArc).onPreferenceChange(ArcHoldingKey.self) { holdingArc=$0 }
            .background(entrySky).navigationTitle("Journal entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button("Edit",systemImage:"pencil") { editing=true } }
                ToolbarItem(placement:.topBarTrailing) { Button(role:.destructive) { confirmDelete=true } label:{ Label("Delete entry",systemImage:"trash") } }
            }
            .confirmationDialog("Delete this night?",isPresented:$confirmDelete,titleVisibility:.visible) {
                Button("Delete entry",role:.destructive) {
                    removed=true
                    context.delete(entry)
                    do { try context.save(); dismiss() } catch { context.rollback(); removed=false; deleteFailed=true }
                }
            } message:{ Text("The notes and photos are removed from this iPhone.") }
            .alert("Unable to delete",isPresented:$deleteFailed) { Button("OK",role:.cancel) {} } message:{ Text("The entry is still here. Try again when space is available.") }.sheet(isPresented:$editing) { NavigationStack { JournalEditorView(existing:entry) }.nyxPresentation() }
    }
}
#Preview("Empty journal") { NavigationStack { JournalView() }.environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).preferredColorScheme(.dark) }
/// The journal's store could not be opened. Everything else works, and the file on disk is left alone.
struct JournalUnavailableBanner:View {
    @Environment(\.nyx) private var palette
    /// The device is nearly full: the one thing that may help is said first.
    var needsSpace=false
    var body:some View {
        Label { Text(needsSpace ? "There is not enough free space to open your journal. Free up some space, then open Nyx again. Everything else works, and Nyx left your journal untouched." : "Your journal could not be opened. Everything else works. Nyx left your journal untouched.").fixedSize(horizontal:false,vertical:true) }
            icon:{ Image(systemName:"externaldrive.badge.exclamationmark").foregroundStyle(palette.caution).accessibilityHidden(true) }
            .font(.subheadline).foregroundStyle(palette.ink)
            .padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .nyxCard(radius:NyxMetrics.rowRadius,fill:palette.panel)
            .accessibilityElement(children:.combine)
    }
}
#Preview("Journal unavailable") { JournalUnavailableBanner().padding(24).background(Color.black).preferredColorScheme(.dark) }
#Preview("Journal unavailable, device full") { JournalUnavailableBanner(needsSpace:true).padding(24).background(Color.black).preferredColorScheme(.dark) }
/// The editor's park row: the system menu and picker, with a label that keeps the park's whole name.
/// The stock menu picker's value is one line, so a long name is cut at large text sizes
/// ("Black…nison" at AX5); here the name sits beside "Park" while it fits and wraps under it when not.
private struct ParkMenuRow:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Binding var parkID:String
    private var name:String { model.park(parkID)?.shortName ?? "" }
    var body:some View {
        if palette.nightVision { PlacePickerOptions(title:model.spots.isEmpty ? "Park" : "Place",selection:$parkID).pickerStyle(.navigationLink) }
        else { menu }
    }
    private var menu:some View {
        Menu {
            PlacePickerOptions(title:"Park",selection:$parkID)
        } label:{
            TitleValueLayout(spacing:12) {
                // "Place" once there are spots to choose from too.
                Text(model.spots.isEmpty ? "Park" : "Place").foregroundStyle(palette.ink)
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Text(name).foregroundStyle(palette.ink).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                    Image(systemName:"chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }
        .accessibilityLabel(model.spots.isEmpty ? "Park" : "Place").accessibilityValue(name)
    }
}
#Preview("Park row, short and long") {
    @Previewable @State var short="jotr"
    @Previewable @State var long="blca"
    Form { ParkMenuRow(parkID:$short); ParkMenuRow(parkID:$long) }.environment(PlanModel()).preferredColorScheme(.dark)
}
#Preview("Park row, AX5") {
    @Previewable @State var long="blca"
    Form { ParkMenuRow(parkID:$long) }.environment(PlanModel()).environment(\.dynamicTypeSize,.accessibility5).preferredColorScheme(.dark)
}
