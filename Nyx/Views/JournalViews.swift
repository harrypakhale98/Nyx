import SwiftUI
import SwiftData
import PhotosUI
import ImageIO

struct JournalView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Query(sort:\JournalEntry.date,order:.reverse) private var entries:[JournalEntry]
    @State private var editing=false
    @State private var deleting:JournalEntry?
    @State private var saveError=false
    @State private var opened:JournalEntry?
    @State private var recap=false
    @State private var width=0.0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var exporting:JournalDocument?
    @State private var importing=false
    @State private var importResult:String?
    /// An export being gathered or an import being read, off the main thread (photos can be many megabytes).
    @State private var working:LocalizedStringKey?
    /// A park dropped onto the journal: a new entry for it, tonight's date.
    @State private var dropped:JournalPrefill?
    /// A wide iPad: your constellation large on the left, the nights themselves on the right.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    var body:some View {
        let nights=model.loggedNights(entries)
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                if model.journalUnavailable { JournalUnavailableBanner(needsSpace:model.journalNeedsSpace) }
                // A journal lives on the device it was written on; say so where a second device is likely.
                if UIDevice.current.userInterfaceIdiom == .pad || sizeClass == .regular {
                    Text("Journals stay on each device. Export to move yours.").font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                // One way into the year: at the top in recap season (December, early January), else under the constellation.
                let season=recapSeason(nights)
                if season { recapCard }
                if wide {
                    HStack(alignment:.top,spacing:28) {
                        YourSkyPanel(nights:nights) { id in opened=entries.first { $0.id==id } }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:24) { if !season && !nights.isEmpty { recapCard }; entryList }.frame(width:min(440,(width*0.4).rounded()))
                    }
                } else {
                    YourSkyPanel(nights:nights) { id in opened=entries.first { $0.id==id } }
                    if !season && !nights.isEmpty { recapCard }
                    entryList
                }
            }.padding(24).readableColumn(wide ? .infinity : WideLayout.readableWidth)
        }.measuringWidth($width).background(NightBackground()).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            .tabRootToolbar()
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Menu {
                    Button("Export journal",systemImage:"square.and.arrow.up") { exportJournal() }
                        .disabled(entries.isEmpty || model.journalUnavailable || working != nil)
                    Button("Import journal",systemImage:"square.and.arrow.down") { importing=true }.disabled(model.journalUnavailable || working != nil)
                } label:{ Image(systemName:"ellipsis").opacity(model.journalUnavailable ? 0.35 : 1) }.accessibilityLabel("Journal options").disabled(model.journalUnavailable) }
                // Nothing is recorded into a journal that could not be opened: it would be lost. Dimmed by hand, since
                // the app's ink foreground style (`RootView`) holds bar symbols at full strength when disabled.
                ToolbarItem(placement:.topBarTrailing) { Button { editing=true } label:{ Image(systemName:"plus").opacity(model.journalUnavailable ? 0.35 : 1) }.accessibilityLabel("Record a night").disabled(model.journalUnavailable) }
            }
            .navigationDestination(item:$opened) { entry in JournalDetailView(entry:entry) }
            .navigationDestination(isPresented:$recap) { YearRecapView(nights:nights) }
            .sheet(isPresented:$editing) { NavigationStack { JournalEditorView() }.nyxPresentation() }
            .sheet(item:$dropped) { prefill in NavigationStack { JournalEditorView(prefill:prefill) }.nyxPresentation() }
            // iPad: drop a park here to start an entry for it (never into a journal that could not open).
            .acceptsPark("Record a night at this park",systemImage:"book.closed") { park in
                guard !model.journalUnavailable else { return }
                dropped=JournalPrefill.dropped(park:park,tonight:model.tonight(park))
            }
            .confirmationDialog("Delete this night?",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting=nil }}),titleVisibility:.visible) { Button("Delete entry",role:.destructive) { if let deleting { context.delete(deleting);do { try context.save() } catch { context.rollback();saveError=true } };deleting=nil } }
            .alert("Unable to delete",isPresented:$saveError) { Button("OK",role:.cancel) {} } message:{ Text("The entry is still here. Try again when space is available.") }
            .fileExporter(isPresented:Binding(get:{ exporting != nil },set:{ if !$0 { exporting=nil } }),document:exporting,contentType:.nyxJournal,
                          defaultFilename:String(localized:"Nyx Journal \(Date.now.formatted(.iso8601.year().month().day()))")) { result in
                if case .failure=result { importResult=String(localized:"The journal could not be exported. Try again when space is available.") }
            }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.nyxJournal]) { result in
                if case .success(let url)=result { Task { await importJournal(url) } }
            }
            .overlay { if let working { WorkingNote(title:working) } }
            .alert("Journal import",isPresented:Binding(get:{ importResult != nil },set:{ if !$0 { importResult=nil } })) { Button("OK",role:.cancel) {} } message:{ Text(importResult ?? "") }
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
    /// Gathers every entry and its photos from the store on a background context, so the photos'
    /// files are read off the main thread; the exporter opens once the archive is ready.
    private func exportJournal() {
        let container=context.container
        working="Preparing your journal"
        Task {
            let archive=await Task.detached(priority:.userInitiated) { () -> JournalArchive? in
                let background=ModelContext(container)
                return (try? background.fetch(FetchDescriptor<JournalEntry>())).map { JournalArchive.make(from:$0) }
            }.value
            working=nil
            if let archive { exporting=JournalDocument(archive:archive) }
            else { importResult=String(localized:"The journal could not be exported. Try again when space is available.") }
        }
    }
    /// Adds the nights the journal does not have yet; nothing already here is changed. The package
    /// is read and its thumbnails drawn off the main thread; only the inserts happen here. A copy
    /// another app left in Documents/Inbox is removed afterwards, imported or not.
    private func importJournal(_ url:URL) async {
        working="Importing your journal"
        model.importingJournal=url
        defer {
            working=nil
            if model.importingJournal == url { model.importingJournal=nil }
            Task.detached(priority:.utility) { JournalInbox.remove(url) }
        }
        let read=await Task.detached(priority:.userInitiated) { () -> (archive:JournalArchive,thumbnails:[UUID:Data])? in
            guard let archive=try? JournalArchive(url:url) else { return nil }
            return (archive,archive.thumbnails())
        }.value
        do {
            guard let read else { throw JournalArchive.ArchiveError.unreadable }
            let result=try read.archive.merge(into:context,thumbnails:read.thumbnails)
            importResult=result.skipped==0 ? String(localized:"Nights added: \(result.added).") : String(localized:"Nights added: \(result.added). Already in your journal: \(result.skipped).")
        } catch {
            context.rollback()
            importResult=String(localized:"This file could not be read as a Nyx journal. Nothing was changed.")
        }
    }
    @ViewBuilder private var entryList: some View {
        if entries.isEmpty { if !model.journalUnavailable { Button("Record a night") { editing=true }.buttonStyle(.borderedProminent).foregroundStyle(Color.black).frame(maxWidth:.infinity) } }
        else {
            LazyVStack(spacing:24) { ForEach(entries) { entry in NavigationLink { JournalDetailView(entry:entry) } label:{ JournalCard(entry:entry) }.buttonStyle(.plain).hoverEffect(.lift).contextMenu { Button("Delete entry",role:.destructive) { deleting=entry } } } }
        }
    }
    /// December (and the first days of January): the year's recap waits at the top of the journal.
    private func recapSeason(_ nights:[LoggedNight])->Bool {
        let now=model.today, calendar=Calendar.current
        let month=calendar.component(.month,from:now), year=calendar.component(.year,from:now)
        let recapYear=month==12 ? year : month==1 && calendar.component(.day,from:now)<=7 ? year-1 : nil
        return recapYear.map { y in nights.contains { calendar.component(.year,from:$0.date)==y } } ?? false
    }
    private var recapCard:some View {
        Button { recap=true } label:{
            Panel { HStack(spacing:14) {
                Image(systemName:"sparkles").font(.title2.weight(.light)).foregroundStyle(palette.accent).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text("Your year under the stars").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    // Written on this iPhone when the system model is available; Nyx's own words otherwise.
                    Text(OnDeviceGuide.available ? "Nights out, your darkest sky, the Moons you met, and a few words on the season, written on this iPhone." : "Nights out, your darkest sky, and the Moons you met.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
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
        ProgressView { Text(title) }.tint(palette.accent).foregroundStyle(palette.ink)
            .padding(.vertical,18).padding(.horizontal,24)
            .background(palette.nightVision ? Color.black : palette.panel,in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).stroke(palette.line,lineWidth:0.5))
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
            Text(moon.map { String(localized:"Bortle \(entry.observedBortle) observed · \($0.name), \(Int(($0.illumination*100).rounded()))% lit") } ?? String(localized:"Observed Bortle class \(entry.observedBortle)"))
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        } }
    }
}
/// Image I/O downsampling: decodes straight to the target size, never the full photo.
nonisolated enum PhotoScaling {
    /// The largest photo the journal accepts, from the editor or from Shortcuts.
    static let maxSourceBytes=40_000_000
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
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
            withAnimation(systemReduceMotion || forcedReduceMotion ? nil : .easeOut(duration:0.25)) { image=decoded }
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
    var parkID="jotr"
    var observedBortle=3
    var notes=""
    var photos:[Data]=[] { didSet { descriptions=Self.aligned(descriptions,to:photos.count) } }
    /// Each photo's description for VoiceOver, in the same order; "" for none.
    var descriptions:[String]=[]
    /// A description the on-device model suggested, per photo, until the person uses or dismisses it.
    var suggestions:[Int:String]=[:]
    var suggesting:Set<Int>=[]
    var loadingPhotos=false
    var error:String?
    var saved=false
    init(entry:JournalEntry?=nil) {
        defer { settled=true }
        if let entry { date=entry.date;parkID=entry.parkID;observedBortle=entry.observedBortle;notes=entry.notes;photos=entry.photos;descriptions=entry.orderedPhotos.map { $0.altText ?? "" } }
        else if let home=UserDefaults.standard.string(forKey:"homePark") { parkID=home }
        #if DEBUG
        if DebugScenario.state=="error" { error=String(localized:"This night could not be stored. Try again when space is available.") }
        if DebugScenario.state=="photo",let image=UIImage(named:"LaunchStars")?.pngData() { photos=[image] }
        if DebugScenario.isEnabled("suggest-fixture"), !photos.isEmpty { suggestions[0]="A dark ridge under a sky full of stars, with a faint band of light above it." }
        #endif
        // Observers do not run inside init: one description per photo from the start.
        descriptions=Self.aligned(descriptions,to:photos.count)
    }
    func load(_ items:[PhotosPickerItem]) async {
        loadingPhotos=true;error=nil;defer { loadingPhotos=false }
        for item in items.prefix(max(0,4-photos.count)) {
            do {
                if let data=try await item.loadTransferable(type:Data.self), data.count<=PhotoScaling.maxSourceBytes {
                    // Decode and shrink off the main thread: a 48 MP photo is hundreds of megabytes decoded.
                    photos.append(await Task.detached(priority:.userInitiated) { PhotoScaling.jpeg(data,maxPixels:2400) ?? data }.value)
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
    }
    /// Asks the on-device model for a draft; it waits beside the field until used or dismissed.
    func suggest(_ index:Int) async {
        guard photos.indices.contains(index), !suggesting.contains(index) else { return }
        suggesting.insert(index); defer { suggesting.remove(index) }
        let data=photos[index]
        if let line=await PhotoDescriber.suggest(data), photos.indices.contains(index), photos[index]==data { suggestions[index]=line }
    }
    func useSuggestion(_ index:Int) {
        guard let line=suggestions[index], descriptions.indices.contains(index) else { return }
        descriptions[index]=line; suggestions[index]=nil
    }
    func save(context:ModelContext,existing:JournalEntry?) -> Bool {
        error=nil
        let entry=existing ?? JournalEntry(date:date,parkID:parkID)
        entry.date=date;entry.parkID=parkID;entry.observedBortle=observedBortle;entry.notes=notes;entry.photos=photos
        // Only what the person wrote or chose to use is kept; a suggestion never saves itself.
        for (photo,text) in zip(entry.orderedPhotos,Self.aligned(descriptions,to:photos.count)) {
            let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
            photo.altText=trimmed.isEmpty ? nil : trimmed
        }
        entry.thumbnail=photos.first.flatMap { PhotoScaling.jpeg($0,maxPixels:900) }
        if existing==nil { context.insert(entry) }
        do { try context.save();saved=true;return true } catch { context.rollback();self.error=String(localized:"This night could not be stored. Try again when space is available.");return false }
    }
}
struct JournalEditorView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editor:JournalEditorModel
    @State private var picker:[PhotosPickerItem]=[]
    var existing:JournalEntry?
    init(existing:JournalEntry?=nil) { self.existing=existing;_editor=State(initialValue:JournalEditorModel(entry:existing)) }
    /// A new entry for a night being kept (field mode at dawn, a park's page the morning after):
    /// the park, the night it began on, the observed-Bortle default and a first line, all editable.
    init(prefill:JournalPrefill) {
        existing=nil
        let editor=JournalEditorModel(entry:nil)
        editor.parkID=prefill.parkID; editor.date=prefill.date; editor.observedBortle=prefill.observedBortle; editor.notes=prefill.notes
        _editor=State(initialValue:editor)
    }
    var body:some View {
        @Bindable var editor=editor
        Form {
            Section("The night") {
                DatePicker("Date",selection:$editor.date,in:...Date.now,displayedComponents:.date).environment(\.timeZone,model.park(editor.parkID)?.timeZone ?? .current)
                Picker("Park",selection:$editor.parkID) { ForEach(model.parks) { Text($0.shortName).tag($0.id) } }
                Stepper(value:$editor.observedBortle,in:1...9) {
                    Text("Observed Bortle: \(editor.observedBortle)").foregroundStyle(palette.ink)
                }.tint(palette.controlTint).foregroundStyle(palette.ink,palette.muted,palette.controlTint)
                Text("Your estimate on the Bortle scale of sky brightness: 1 is the darkest sky, 9 an inner-city sky.").font(.caption).foregroundStyle(palette.muted)
            }
            Section("What you noticed") { TextEditor(text:$editor.notes).frame(minHeight:160).accessibilityLabel("Observation notes") }
            Section {
                ForEach(Array(editor.photos.enumerated()),id:\.offset) { index,data in
                    PhotoDescriptionRow(editor:editor,index:index,data:data)
                }
                if editor.loadingPhotos { ProgressView("Adding photo") }
                PhotosPicker(selection:$picker,maxSelectionCount:max(0,4-editor.photos.count),matching:.images) { Label("Choose photos",systemImage:"photo") }.disabled(editor.photos.count>=4 || editor.loadingPhotos)
            } header:{ Text("Photos") } footer:{ Text("Choose up to four photos. Nyx sees only the photos you select. They stay on this iPhone. A short description lets VoiceOver say what each one shows.").foregroundStyle(palette.muted) }
            if let error=editor.error { Section { Text(error).foregroundStyle(palette.accent) } }
        }.readableForm().defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).navigationTitle(existing==nil ? "Record a night" : "Edit night").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // A new entry starts on the night just seen, not the calendar day it is written on.
            if existing==nil, !editor.dateChosen, let park=model.park(editor.parkID) { editor.date=min(.now,park.lastNightBegun(at:.now)) }
        }
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } };ToolbarItem(placement:.confirmationAction) { Button("Save") { if editor.save(context:context,existing:existing) { dismiss() } }.disabled(editor.loadingPhotos) } }
            .onChange(of:picker) { _,items in Task { await editor.load(items);picker=[] } }
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
                PhotoView(data:data,maxPixels:240,fill:true).frame(width:80,height:80).clipShape(RoundedRectangle(cornerRadius:10))
                    .accessibilityLabel(JournalPhotoLabel.text(description.wrappedValue,index:index))
                TextField("Describe this photo",text:description,axis:.vertical).lineLimit(1...4)
                    .accessibilityLabel("Description of photo \(index+1)")
                    .accessibilityHint("VoiceOver reads this when the photo is shown.")
            }
            if let suggestion=editor.suggestions[index] {
                VStack(alignment:.leading,spacing:8) {
                    Text("Suggested on this iPhone").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                    Text(suggestion).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:16) {
                        Button("Use this") { editor.useSuggestion(index) }.buttonStyle(.borderless).foregroundStyle(palette.accent)
                        Button("Dismiss") { editor.suggestions[index]=nil }.buttonStyle(.borderless).foregroundStyle(palette.muted)
                    }.frame(minHeight:44)
                }
                .padding(12).frame(maxWidth:.infinity,alignment:.leading)
                .background(RoundedRectangle(cornerRadius:12).stroke(palette.line,lineWidth:0.5))
                .accessibilityElement(children:.contain)
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
                    .buttonStyle(.borderless).foregroundStyle(palette.accent)
                    .accessibilityHint("Drafts one line on this iPhone for you to read and edit. Nothing is saved until you use it.")
            }
        }
        Button(role:.destructive) { editor.removePhoto(at:index) } label:{ Text("Remove photo").foregroundStyle(palette.accent).frame(minHeight:44).contentShape(Rectangle()) }
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
            HStack(spacing:18) {
                MoonView(geometry:moon.geometry,moment:String(localized:"at \(park.time(moon.moment))")).frame(width:64,height:64)
                VStack(alignment:.leading,spacing:4) {
                    Text("The Moon that night").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                    Text("\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.system(.title3,design:.serif))
                    Text("Observed Bortle class \(entry.observedBortle)").font(.subheadline).foregroundStyle(palette.muted)
                }
            }
        } else { Text("Observed Bortle class \(entry.observedBortle)").font(.subheadline).foregroundStyle(palette.muted) }
    }
    var body:some View {
        ScrollView { if !removed { VStack(alignment:.leading,spacing:24) { Eyebrow(text:"A night remembered");Text(model.park(entry.parkID)?.shortName ?? String(localized:"A night outside")).font(.system(.largeTitle,design:.serif));Text(model.park(entry.parkID)?.dateLabel(entry.date) ?? entry.date.formatted(date:.abbreviated,time:.omitted)).font(.subheadline).foregroundStyle(palette.muted).padding(.top,-14);moonThatNight;Divider().overlay(palette.line);Text(entry.notes).font(.system(.body,design:.serif)).lineSpacing(7);ForEach(Array(entry.orderedPhotos.enumerated()),id:\.offset) { i,photo in PhotoView(data:photo.data,maxPixels:1600).clipShape(RoundedRectangle(cornerRadius:20)).accessibilityLabel(JournalPhotoLabel.text(photo.altText,index:i)) };Divider().overlay(palette.line);GlobeAtNightLink() }.padding(24).readableColumn(WideLayout.proseWidth) } }.background(entrySky).navigationTitle("Journal entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button("Edit") { editing=true } }
                ToolbarItem(placement:.topBarTrailing) { Button(role:.destructive) { confirmDelete=true } label:{ Image(systemName:"trash") }.accessibilityLabel("Delete entry") }
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
            icon:{ Image(systemName:"externaldrive.badge.exclamationmark").foregroundStyle(palette.accent).accessibilityHidden(true) }
            .font(.subheadline).foregroundStyle(palette.ink)
            .padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(palette.panel,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(palette.line,lineWidth:0.5))
            .accessibilityElement(children:.combine)
    }
}
#Preview("Journal unavailable") { JournalUnavailableBanner().padding(24).background(Color.black).preferredColorScheme(.dark) }
#Preview("Journal unavailable, device full") { JournalUnavailableBanner(needsSpace:true).padding(24).background(Color.black).preferredColorScheme(.dark) }
