import SwiftUI

/// "Where to stay": the park's campgrounds as the National Park Service lists them, the next
/// question after where and when. Reservations open in Safari, only on recreation.gov or nps.gov.
/// Nyx never knows availability, and says so. Campgrounds for every park arrive in one request,
/// the first time any park's panel appears, and are kept seven days.
struct WhereToStayPanel: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    /// Campgrounds shown before "Show all": most parks have three or fewer; Isle Royale has 36.
    var initialCount = 4
    @State private var showsAll=false
    @State private var loading=false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Eyebrow(text:"Where to stay")
            // The honest limit comes first, before the list it qualifies.
            if !(model.campgrounds?.list(park).isEmpty ?? true) {
                Text("Campgrounds fill early on new-moon weekends. Nyx does not know availability.")
                    .font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            }
            content
            if let updated=model.campgrounds?.updated {
                Text("From the National Park Service, \(park.timestamp(updated)).").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius:24).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:24).stroke(palette.line,lineWidth:0.5))
        .task {
            loading=model.campgrounds == nil
            await model.refreshCampgrounds()
            loading=false
        }
    }
    @ViewBuilder private var content: some View {
        let list=model.campgrounds?.list(park) ?? []
        if !list.isEmpty {
            let shown=showsAll ? list : Array(list.prefix(initialCount))
            VStack(alignment:.leading,spacing:0) {
                ForEach(Array(shown.enumerated()),id:\.element.id) { index,campground in
                    if index>0 { Divider().overlay(palette.line) }
                    CampgroundRow(campground:campground).padding(.vertical,12)
                }
            }
            if list.count>shown.count {
                Button { showsAll=true } label:{ Text("Show all \(list.count) campgrounds").frame(minHeight:44) }
                    .font(.subheadline.weight(.medium)).foregroundStyle(palette.accent)
            }
        } else if model.campgrounds != nil {
            Text("The National Park Service lists no campgrounds in this park. Its website covers other places to stay nearby.")
                .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            planLink
        } else if loading && model.npsEnabled {
            HStack(spacing:10) { ProgressView(); Text("Loading campgrounds") }.font(.subheadline).foregroundStyle(palette.muted)
        } else {
            Text(model.npsEnabled ? "Campgrounds appear once Nyx reaches the National Park Service." : "Park updates are off in Your privacy, so campgrounds are not loaded.")
                .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            planLink
        }
    }
    @ViewBuilder private var planLink: some View {
        if let url=StayLink.planYourVisit(park) {
            Link(destination:url) { Label("Plan your visit on nps.gov",systemImage:"safari").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                .font(.subheadline.weight(.medium)).foregroundStyle(palette.accent).accessibilityHint(Text("Opens in Safari."))
        }
    }
}
/// One campground: its name, the NPS's first sentence about it, its sites, its access note and,
/// when it takes reservations on recreation.gov or nps.gov, the link to book.
private struct CampgroundRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let campground: Campground
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(campground.name).font(.system(.headline,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                .accessibilityAddTraits(.isHeader)
            if let sites { Text(sites).font(.subheadline.monospacedDigit()).foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.86)).fixedSize(horizontal:false,vertical:true) }
            if !campground.summary.isEmpty { Text(campground.summary).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if let access=campground.wheelchairAccess {
                Label { Text(access).fixedSize(horizontal:false,vertical:true) } icon:{ if !typeSize.isAccessibilitySize { Image(systemName:"figure.roll").accessibilityHidden(true) } }
                    .font(.subheadline).foregroundStyle(palette.muted)
                    .accessibilityLabel(Text("Access: \(access)"))
            }
            if let url=campground.reservationURL, let site=campground.reservationSite {
                Link(destination:url) { Label("Reserve on \(site)",systemImage:"safari").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .font(.subheadline.weight(.medium)).foregroundStyle(palette.accent)
                    .accessibilityLabel(Text("Reserve \(campground.name) on \(site)")).accessibilityHint(Text("Opens in Safari."))
            } else if (campground.firstComeSites ?? 0)>0 && (campground.reservableSites ?? 0) == 0 {
                Text("First come, first served. No reservations.").font(.subheadline).foregroundStyle(palette.muted)
            } else if let page=campground.pageURL {
                // Booked elsewhere (a concessioner Nyx does not link): the park's own page says how.
                Link(destination:page) { Label("How to book, on nps.gov",systemImage:"safari").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .font(.subheadline.weight(.medium)).foregroundStyle(palette.accent)
                    .accessibilityLabel(Text("How to book \(campground.name), on nps.gov")).accessibilityHint(Text("Opens in Safari."))
            }
        }
    }
    /// "62 reservable sites", "15 first-come sites", or both; nothing when the NPS gives no counts.
    private var sites: String? {
        let reservable=campground.reservableSites ?? 0, first=campground.firstComeSites ?? 0
        switch (reservable>0,first>0) {
        case (true,true): return String(localized:"\(reservable) reservable sites · \(first) first-come")
        case (true,false): return String(localized:"\(reservable) reservable sites")
        case (false,true): return String(localized:"\(first) first-come sites")
        case (false,false): return campground.totalSites.flatMap { $0>0 ? String(localized:"\($0) sites") : nil }
        }
    }
}
/// Pages "Where to stay" opens in Safari at a tap (SwiftUI `Link`), never fetched by Nyx. Reservation
/// links come from the NPS data and are kept only on `Campground.reservationHosts`.
enum StayLink {
    static func planYourVisit(_ park:Park)->URL? { page(host:"www.nps.gov",path:"/\(park.apiCode)/planyourvisit/index.htm") }
    /// The federal booking site's home, for the reservation hosts' list (`verify_release.py`).
    static let recreationGov=page(host:"www.recreation.gov")
    private static func page(host:String,path:String="")->URL? {
        var components=URLComponents(); components.scheme="https"; components.host=host; components.path=path
        return components.url
    }
}

#if DEBUG
private struct StayPreview: View {
    let park: String
    var cache: CampgroundsCache?
    @State private var model=PlanModel()
    var body: some View {
        ScrollView { if let p=model.park(park) { WhereToStayPanel(park:p).padding() } }
            .background(Color.black).environment(model).preferredColorScheme(.dark)
            .onAppear { model.campgrounds=cache }
    }
}
private let previewCache=CampgroundsCache(updated:.now,campgrounds:["jotr":[
    Campground(id:"1",name:"Cottonwood Campground",parkCode:"jotr",summary:"The Cottonwood Campground is reservation only and has 62 sites, potable water and flush toilets.",reservationURL:StayLink.recreationGov,pageURL:nil,reservableSites:62,firstComeSites:0,totalSites:62,wheelchairAccess:"Most campsites have uneven terrain.",adaNote:nil),
    Campground(id:"2",name:"White Tank Campground",parkCode:"jotr",summary:"This is a small campground with 15 sites.",reservationURL:nil,pageURL:nil,reservableSites:0,firstComeSites:15,totalSites:15,wheelchairAccess:nil,adaNote:nil)],"cave":[]])
#Preview("Where to stay") { StayPreview(park:"jotr",cache:previewCache) }
#Preview("No campgrounds") { StayPreview(park:"cave",cache:previewCache) }
#Preview("Not loaded • AX5") { StayPreview(park:"jotr",cache:nil).dynamicTypeSize(.accessibility5) }
#Preview("Night vision") { StayPreview(park:"jotr",cache:previewCache).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)) }
#endif
