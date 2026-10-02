import SwiftUI
import SwiftData
import PhotosUI

struct JournalView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Query(sort:\JournalEntry.date,order:.reverse) private var entries:[JournalEntry]
    @State private var editing=false
    @State private var deleting:JournalEntry?
    @State private var saveError=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Eyebrow(text:"Keep a little of the night")
                Text("Under the same sky").font(.system(.largeTitle,design:.serif))
                if entries.isEmpty { CalmState(symbol:"book.closed",title:"Your first night belongs here",message:"Record what you saw, how the sky felt, and the place you found it. Every entry stays on this iPhone.");Button("Record a night") { editing=true }.buttonStyle(.borderedProminent).foregroundStyle(Color.black).frame(maxWidth:.infinity) }
                else {
                    ForEach(entries) { entry in NavigationLink { JournalDetailView(entry:entry) } label:{ Panel { VStack(alignment:.leading,spacing:8) { Text(model.park(entry.parkID)?.shortName ?? String(localized:"A night outside")).font(.system(.title2,design:.serif));Text(model.park(entry.parkID)?.dateLabel(entry.date) ?? entry.date.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(palette.muted);Text(entry.notes.isEmpty ? String(localized:"Observed Bortle class \(entry.observedBortle)") : entry.notes).font(.subheadline).lineLimit(3).foregroundStyle(palette.muted) } } }.buttonStyle(.plain).contextMenu { Button("Delete entry",role:.destructive) { deleting=entry } } }
                    if OnDeviceGuide.available { NavigationLink("Reflect on this season") { GuideView(mode:.recap) }.buttonStyle(.bordered) }
                }
            }.padding(24)
        }.background(NightBackground()).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button { editing=true } label:{ Image(systemName:"plus") }.accessibilityLabel("Record a night") } }
            .sheet(isPresented:$editing) { NavigationStack { JournalEditorView() }.nyxPresentation() }
            .confirmationDialog("Delete this night?",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting=nil }}),titleVisibility:.visible) { Button("Delete entry",role:.destructive) { if let deleting { context.delete(deleting);do { try context.save() } catch { context.rollback();saveError=true } };deleting=nil } }
            .alert("Unable to delete",isPresented:$saveError) { Button("OK",role:.cancel) {} } message:{ Text("The entry is still here. Try again when space is available.") }
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
        #if DEBUG
        if DebugScenario.state=="error" { error=String(localized:"This night could not be stored. Try again when space is available.") }
        if DebugScenario.state=="photo",let image=UIImage(named:"LaunchStars")?.pngData() { photos=[image] }
        #endif
    }
    func load(_ items:[PhotosPickerItem]) async {
        loadingPhotos=true;defer { loadingPhotos=false }
        for item in items.prefix(max(0,4-photos.count)) {
            do {
                if let data=try await item.loadTransferable(type:Data.self), data.count<=20_000_000 { photos.append(data) }
                else { error=String(localized:"This photo is too large. Choose a smaller image.") }
            } catch { self.error=String(localized:"The photo could not be loaded. Try choosing it again.") }
        }
    }
    func save(context:ModelContext,existing:JournalEntry?) -> Bool {
        let entry=existing ?? JournalEntry(date:date,parkID:parkID)
        entry.date=date;entry.parkID=parkID;entry.observedBortle=observedBortle;entry.notes=notes;entry.photos=photos
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
                Text("Your estimate of artificial sky brightness. Class 1 is darkest.").font(.caption).foregroundStyle(palette.muted)
            }
            Section("What you noticed") { TextEditor(text:$editor.notes).frame(minHeight:160).accessibilityLabel("Observation notes") }
            Section {
                ForEach(Array(editor.photos.enumerated()),id:\.offset) { index,data in
                    HStack { if let image=UIImage(data:data) { Image(uiImage:image).resizable().scaledToFill().frame(width:80,height:80).clipped().accessibilityIgnoresInvertColors().accessibilityLabel("Journal photo \(index+1)") };Spacer();Button(role:.destructive) { editor.photos.remove(at:index) } label:{ Text("Remove photo").foregroundStyle(palette.accent) } }
                }
                if editor.loadingPhotos { ProgressView("Adding photo") }
                PhotosPicker(selection:$picker,maxSelectionCount:max(0,4-editor.photos.count),matching:.images) { Label("Choose photos",systemImage:"photo") }.disabled(editor.photos.count>=4 || editor.loadingPhotos)
            } header:{ Text("Photos") } footer:{ Text("Choose up to four photos. Nyx sees only the photos you select. They stay on this iPhone.").foregroundStyle(palette.muted) }
            if let error=editor.error { Section { Text(error).foregroundStyle(palette.accent) } }
        }.defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).navigationTitle(existing==nil ? "Record a night" : "Edit night").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } };ToolbarItem(placement:.confirmationAction) { Button("Save") { if editor.save(context:context,existing:existing) { dismiss() } }.disabled(editor.loadingPhotos) } }
            .onChange(of:picker) { _,items in Task { await editor.load(items);picker=[] } }
            .sensoryFeedback(.success,trigger:editor.saved)
    }
}
struct JournalDetailView:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    let entry:JournalEntry
    @State private var editing=false
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) { Eyebrow(text:"A night remembered");Text(model.park(entry.parkID)?.shortName ?? String(localized:"A night outside")).font(.system(.largeTitle,design:.serif));Text(model.park(entry.parkID)?.dateLabel(entry.date) ?? entry.date.formatted(date:.abbreviated,time:.omitted));Text("Observed Bortle class \(entry.observedBortle)").font(.subheadline).foregroundStyle(palette.muted);Text(entry.notes).font(.system(.body,design:.serif)).lineSpacing(7);ForEach(Array(entry.photos.enumerated()),id:\.offset) { i,data in if let image=UIImage(data:data) { Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:20)).accessibilityIgnoresInvertColors().accessibilityLabel("Journal photo \(i+1)") } } }.padding(24) }.background(NightBackground()).navigationTitle("Journal entry").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Edit") { editing=true } } }.sheet(isPresented:$editing) { NavigationStack { JournalEditorView(existing:entry) }.nyxPresentation() }
    }
}
#Preview("Empty journal") { NavigationStack { JournalView() }.environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).preferredColorScheme(.dark) }
