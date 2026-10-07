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
    /// A wide iPad: your constellation large on the left, the nights themselves on the right.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    var body:some View {
        let nights=model.loggedNights(entries)
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Eyebrow(text:"Keep a little of the night")
                Text("Under the same sky").font(.system(.largeTitle,design:.serif))
                if recapSeason(nights) { recapCard }
                if wide {
                    HStack(alignment:.top,spacing:28) {
                        YourSkyPanel(nights:nights) { id in opened=entries.first { $0.id==id } }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:24) { entryList }.frame(width:min(440,(width*0.4).rounded()))
                    }
                } else {
                    YourSkyPanel(nights:nights) { id in opened=entries.first { $0.id==id } }
                    entryList
                }
            }.padding(24).readableColumn(wide ? .infinity : WideLayout.readableWidth)
        }.measuringWidth($width).background(NightBackground()).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Menu {
                    Button("Year under the stars",systemImage:"sparkles") { recap=true }.disabled(entries.isEmpty)
                } label:{ Image(systemName:"ellipsis") }.accessibilityLabel("Journal options") }
                ToolbarItem(placement:.topBarTrailing) { Button { editing=true } label:{ Image(systemName:"plus") }.accessibilityLabel("Record a night") }
            }
            .navigationDestination(item:$opened) { entry in JournalDetailView(entry:entry) }
            .navigationDestination(isPresented:$recap) { YearRecapView(nights:nights) }
            .sheet(isPresented:$editing) { NavigationStack { JournalEditorView() }.nyxPresentation() }
            .confirmationDialog("Delete this night?",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting=nil }}),titleVisibility:.visible) { Button("Delete entry",role:.destructive) { if let deleting { context.delete(deleting);do { try context.save() } catch { context.rollback();saveError=true } };deleting=nil } }
            .alert("Unable to delete",isPresented:$saveError) { Button("OK",role:.cancel) {} } message:{ Text("The entry is still here. Try again when space is available.") }
    }
    @ViewBuilder private var entryList: some View {
        if entries.isEmpty { Button("Record a night") { editing=true }.buttonStyle(.borderedProminent).foregroundStyle(Color.black).frame(maxWidth:.infinity) }
        else {
            LazyVStack(spacing:24) { ForEach(entries) { entry in NavigationLink { JournalDetailView(entry:entry) } label:{ JournalCard(entry:entry) }.buttonStyle(.plain).hoverEffect(.lift).contextMenu { Button("Delete entry",role:.destructive) { deleting=entry } } } }
            if OnDeviceGuide.available { NavigationLink("Reflect on this season") { GuideView(mode:.recap) }.buttonStyle(.bordered) }
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
                    Text("Your year under the stars").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
                    Text("Nights out, your darkest sky, and the Moons you met.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:0)
            } }
        }.buttonStyle(.plain).accessibilityElement(children:.combine).accessibilityAddTraits(.isButton)
    }
}
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
    var date=Date.now
    var parkID="jotr"
    var observedBortle=3
    var notes=""
    var photos:[Data]=[]
    var loadingPhotos=false
    var error:String?
    var saved=false
    init(entry:JournalEntry?=nil) {
        if let entry { date=entry.date;parkID=entry.parkID;observedBortle=entry.observedBortle;notes=entry.notes;photos=entry.photos }
        else if let home=UserDefaults.standard.string(forKey:"homePark") { parkID=home }
        #if DEBUG
        if DebugScenario.state=="error" { error=String(localized:"This night could not be stored. Try again when space is available.") }
        if DebugScenario.state=="photo",let image=UIImage(named:"LaunchStars")?.pngData() { photos=[image] }
        #endif
    }
    func load(_ items:[PhotosPickerItem]) async {
        loadingPhotos=true;error=nil;defer { loadingPhotos=false }
        for item in items.prefix(max(0,4-photos.count)) {
            do {
                if let data=try await item.loadTransferable(type:Data.self), data.count<=40_000_000 {
                    // Decode and shrink off the main thread: a 48 MP photo is hundreds of megabytes decoded.
                    photos.append(await Task.detached(priority:.userInitiated) { PhotoScaling.jpeg(data,maxPixels:2400) ?? data }.value)
                }
                else { error=String(localized:"This photo is too large. Choose a smaller image.") }
            } catch { self.error=String(localized:"The photo could not be loaded. Try choosing it again.") }
        }
    }
    func save(context:ModelContext,existing:JournalEntry?) -> Bool {
        error=nil
        let entry=existing ?? JournalEntry(date:date,parkID:parkID)
        entry.date=date;entry.parkID=parkID;entry.observedBortle=observedBortle;entry.notes=notes;entry.photos=photos
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
                    HStack {
                        PhotoView(data:data,maxPixels:240,fill:true).frame(width:80,height:80).clipShape(RoundedRectangle(cornerRadius:10)).accessibilityLabel("Journal photo \(index+1)")
                        Spacer()
                        // Borderless, so only the button removes the photo, not a tap anywhere in the row.
                        Button(role:.destructive) { editor.photos.remove(at:index) } label:{ Text("Remove photo").foregroundStyle(palette.accent).frame(minHeight:44).contentShape(Rectangle()) }
                            .buttonStyle(.borderless).accessibilityLabel("Remove photo \(index+1)")
                    }
                }
                if editor.loadingPhotos { ProgressView("Adding photo") }
                PhotosPicker(selection:$picker,maxSelectionCount:max(0,4-editor.photos.count),matching:.images) { Label("Choose photos",systemImage:"photo") }.disabled(editor.photos.count>=4 || editor.loadingPhotos)
            } header:{ Text("Photos") } footer:{ Text("Choose up to four photos. Nyx sees only the photos you select. They stay on this iPhone.").foregroundStyle(palette.muted) }
            if let error=editor.error { Section { Text(error).foregroundStyle(palette.accent) } }
        }.readableForm().defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).navigationTitle(existing==nil ? "Record a night" : "Edit night").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } };ToolbarItem(placement:.confirmationAction) { Button("Save") { if editor.save(context:context,existing:existing) { dismiss() } }.disabled(editor.loadingPhotos) } }
            .onChange(of:picker) { _,items in Task { await editor.load(items);picker=[] } }
            .sensoryFeedback(.success,trigger:editor.saved)
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
        ScrollView { if !removed { VStack(alignment:.leading,spacing:24) { Eyebrow(text:"A night remembered");Text(model.park(entry.parkID)?.shortName ?? String(localized:"A night outside")).font(.system(.largeTitle,design:.serif));Text(model.park(entry.parkID)?.dateLabel(entry.date) ?? entry.date.formatted(date:.abbreviated,time:.omitted)).font(.subheadline).foregroundStyle(palette.muted).padding(.top,-14);moonThatNight;Divider().overlay(palette.line);Text(entry.notes).font(.system(.body,design:.serif)).lineSpacing(7);ForEach(Array(entry.photos.enumerated()),id:\.offset) { i,data in PhotoView(data:data,maxPixels:1600).clipShape(RoundedRectangle(cornerRadius:20)).accessibilityLabel("Journal photo \(i+1)") };Divider().overlay(palette.line);GlobeAtNightLink() }.padding(24).readableColumn(WideLayout.proseWidth) } }.background(entrySky).navigationTitle("Journal entry").navigationBarTitleDisplayMode(.inline)
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
