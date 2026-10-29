import SwiftUI

struct OnboardingView:View {
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Landscape on iPhone (and iPhone Duo's outer display turned): the art beside the words, so the
    /// words are never pushed under the page's controls.
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.horizontalSizeClass) private var horizontalSize
    /// Also in a wide, short window of regular height (iPhone Duo's inner display, 878 × 669), where
    /// stacked art pushed the message under the fade.
    private var beside:Bool { (verticalSize == .compact || (size.width>size.height && size.height<720)) && !typeSize.isAccessibilitySize }
    @State private var size=CGSize.zero
    @State private var fold:Fold?
    /// Compact height at any text size: Skip joins the dots and Continue in one row at the bottom and
    /// the margins tighten, so the page keeps most of the height.
    private var compactHeight:Bool { verticalSize == .compact }
    /// A short portrait window (667 pt phones): Skip moves beside the dots and the art and margins
    /// shrink, so each page's message clears the fade without scrolling.
    private var short:Bool { size.height>0 && size.height<720 && !beside && !compactHeight }
    @Environment(\.nyx) private var palette
    @MotionReduced private var reduceMotion: Bool
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @State private var page=DebugScenario.onboardingPage
    /// The fade above the page dots grows with the text, so a large line fades out rather than being sliced.
    @ScaledMetric(relativeTo:.body) private var fade=24.0
    let finish:()->Void
    private let titles:[LocalizedStringKey]=["Where and when\nthe sky is darkest","A darker sky.\nA clearer plan.","Made for dark eyes"]
    /// The first page names what Nyx scores everywhere: the US parks are part of the world it covers.
    private var messages:[LocalizedStringKey] {[
        "Nyx compares national parks and dark-sky places around the world, night by night, so you know where to go and which night to take off.",
        "Moonlight, clouds, sky glow and true darkness become one score. Every estimate tells you what is still unknown.",
        "Turn the screen red at any time, here or from Control Center. Nyx has no account, no ads, no tracking. Your journal never leaves this phone.",
    ]}
    var body:some View {
        VStack(spacing:0) {
            // Tracking trails the X, so the wordmark is inset by one tracking step to sit on centre.
            if !compactHeight && !short {
                HStack { Spacer();skip }.overlay { if !typeSize.isAccessibilitySize { Text("NYX").font(.caption).tracking(8).padding(.leading,8).accessibilityHidden(true) } }.padding(.leading,wordsInset).padding(.horizontal,28).padding(.top,28)
            }
            TabView(selection:$page) {
                ForEach(0..<3,id:\.self) { index in
                    ScrollView {
                        if let halves {
                            // iPhone Duo open: the art on the leading side of the fold, the words on the trailing side.
                            HStack(spacing:0) {
                                art(index).frame(maxWidth:320).padding(.horizontal,20).frame(width:halves.leading)
                                Color.clear.frame(width:halves.gap)
                                words(index).padding(.horizontal,24).frame(width:halves.trailing)
                            }.padding(.vertical,12)
                        } else {
                            let layout=beside ? AnyLayout(HStackLayout(spacing:36)) : AnyLayout(VStackLayout(spacing:gap(index)))
                            layout {
                                art(index).frame(maxWidth:beside ? 320 : nil)
                                words(index)
                            }.padding(.horizontal,compactHeight || short ? 20 : 28).padding(.vertical,index==1 || typeSize.isAccessibilitySize || beside || short ? 12 : 28).frame(maxWidth:beside ? 760 : 560).frame(maxWidth:.infinity)
                        }
                    }.scrollBounceBehavior(.basedOnSize).defaultScrollAnchor(.center,for:.alignment)
                    // Copy taller than the page shows its scroll indicator once, so "more below" is never only a fade.
                    .scrollIndicatorsFlash(onAppear:true)
                    // Copy that runs past the controls fades out instead of being cut mid-line.
                    // At compact height the fade stays short, so a large line is not lost in it.
                    .mask { VStack(spacing:0) { Color.black;LinearGradient(colors:[.black,.clear],startPoint:.top,endPoint:.bottom).frame(height:compactHeight || short ? min(fade,32) : fade) } }
                    .tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode:.never))
            if compactHeight {
                // Dots, Skip and Continue in one row; at the largest sizes, Continue goes under the other two.
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:20) { dots;Spacer(minLength:8);skip;proceed }
                    VStack(spacing:8) { HStack { dots;Spacer(minLength:8);skip };proceed }
                }.padding(.horizontal,20).padding(.top,4).padding(.bottom,8)
            } else if short {
                // Dots centred with Skip beside them (a hidden twin balances it); dots first when Skip's label is too wide.
                VStack(spacing:8) {
                    ViewThatFits(in:.horizontal) {
                        HStack { skip.hidden();Spacer(minLength:8);dots;Spacer(minLength:8);skip }
                        HStack { dots;Spacer(minLength:8);skip }
                    }
                    proceed
                }.padding(.horizontal,20).padding(.bottom,12)
            } else {
                VStack(spacing:20) { dots;proceed }.frame(maxWidth:.infinity).padding(.leading,wordsInset).padding(.bottom,28)
            }
        }.background(NightBackground(score:page==1 ? 94 : nil)).foregroundStyle(palette.ink)
        .onGeometryChange(for:CGSize.self) { $0.size } action:{ size=$0 }
        .readingFold($fold)
    }
    private func words(_ index:Int)->some View {
        VStack(spacing:beside ? 16 : gap(index)) {
            Text(titles[index]).font(.system(beside || short ? .title : .largeTitle,design:.serif)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            Text(messages[index]).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
            if index==2 { redToggle }
        }
    }
    /// iPhone Duo open, beside: the widths either side of the fold, each at least 260 pt; nil without a fold.
    private var halves:(leading:Double,gap:Double,trailing:Double)? {
        guard beside, let fold, fold.dividesWidth, fold.minX>=260, size.width-fold.maxX>=260 else { return nil }
        return (fold.minX,fold.width,size.width-fold.maxX)
    }
    /// Where the words' side begins across a fold, so the wordmark, dots and Continue sit over the words, not the crease.
    private var wordsInset:Double { halves.map { $0.leading+$0.gap } ?? 0 }
    private var skip:some View { Button("Skip") { finish() }.frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
    private var dots:some View {
        HStack(spacing:12) { ForEach(0..<3,id:\.self) { i in Capsule().fill(i==page ? palette.ink : palette.line).frame(width:i==page ? 18 : 5,height:5) } }
            .animation(reduceMotion ? nil : NyxMotion.spring,value:page)
            .frame(minWidth:88,minHeight:44).contentShape(Rectangle())
            // Swipe up or down with VoiceOver to turn the page, as the dots suggest.
            .accessibilityElement().accessibilityLabel("Introduction").accessibilityValue("Page \(page+1) of 3")
            .accessibilityAdjustableAction { direction in
                let next=switch direction {
                case .increment: min(page+1,2)
                case .decrement: max(page-1,0)
                @unknown default: page
                }
                guard next != page else { return }
                withAnimation(reduceMotion ? nil : NyxMotion.spring) { page=next }
            }
    }
    private var proceed:some View {
        Button(page==2 ? "Show me tonight" : "Continue") { if page==2 { finish() } else { withAnimation(reduceMotion ? nil : NyxMotion.spring) { page+=1 } } }
            .secondaryAction().controlSize(.large)
    }
    /// A large window (an iPad, either way up) draws the art at the size its other pages give the dial, not a phone's.
    private var roomy:Bool { horizontalSize == .regular && verticalSize == .regular && min(size.width,size.height)>=700 }
    private var moonSize:CGFloat { beside ? 130 : short ? 140 : roomy ? 260 : 170 }
    private var moonPadding:CGFloat { beside ? 8 : short ? 12 : 24 }
    private func gap(_ index:Int)->CGFloat { index==1 && !typeSize.isAccessibilitySize ? (short ? 12 : 16) : 28 }
    /// At accessibility sizes the decorative Moon is left out, so the headline and the first lines
    /// of the message sit above the page dots rather than behind the fade.
    @ViewBuilder private func art(_ index:Int)->some View {
        switch index {
        case 0: if !typeSize.isAccessibilitySize { OnboardingMoon(daysAfterNew:3).frame(width:moonSize,height:moonSize).padding(.vertical,moonPadding) }
        case 1: ScoreAnatomy(active:page==1,roomy:roomy,compact:short)
        // The last page ends bright: a waxing gibbous Moon, which turns red with the switch below it.
        default: if !typeSize.isAccessibilitySize { OnboardingMoon(daysAfterNew:11).frame(width:moonSize,height:moonSize).padding(.vertical,moonPadding) }
        }
    }
    /// The real night-vision switch: the whole app, this page included, turns red on the shared spring.
    private var redToggle:some View {
        // A rounded rectangle at accessibility sizes, where the label wraps and a capsule's rim would meet the icon.
        let shape=typeSize.isAccessibilitySize ? AnyShape(RoundedRectangle(cornerRadius:22,style:.continuous)) : AnyShape(Capsule())
        return Toggle(isOn:Binding(get:{ nightVision },set:{ NightVisionMode.turnedByHand(); nightVision=$0 })) {
            Label { Text("Night vision") } icon:{ Image(systemName:nightVision ? "flashlight.on.circle.fill" : "flashlight.off.circle").foregroundStyle(palette.ink) }.font(.headline)
        }
        .tint(palette.controlTint)
        .padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:340,minHeight:56)
        .background(shape.fill(palette.panel)).overlay(shape.stroke(palette.line,lineWidth:0.5*palette.stroke))
        // The soft tap of the turn comes once, from RootView, whichever switch changed it.
        .accessibilityHint("Turns the screen red. You can change it any time.")
    }
}
/// A real Moon over the starting park: a young crescent, or the new Moon's earthlit disc.
/// Computed from the coming new moon, so the art always matches this month's sky.
private struct OnboardingMoon:View {
    @Environment(PlanModel.self) private var model
    let daysAfterNew:Double
    /// Decoration beside the words, which say what it shows: VoiceOver passes it by.
    var body:some View { moon.accessibilityHidden(true) }
    @ViewBuilder private var moon:some View {
        let engine=AstronomyEngine(), park=model.home
        // Walk forward to the next new moon (phase fraction wraps past 0), then add the offset.
        let now=Date.now, fraction=engine.moonPhase(at:now).fraction
        let newMoon=now.addingTimeInterval((1-fraction)*AstronomyEngine.synodicDays*86400)
        let evening=newMoon.addingTimeInterval(daysAfterNew*86400)
        if let park {
            let sky=engine.conditions(for:park,on:park.evening(evening))
            // A young crescent is seen low in the west after sunset, not at its highest (often in daylight).
            let at=daysAfterNew>0 ? (sky.sunset ?? evening).addingTimeInterval(3600) : engine.moonViewTime(for:sky,park:park)
            MoonView(geometry:engine.moonGeometry(for:park,at:at))
        } else { MoonDisc(illumination:daysAfterNew>0 ? 0.18 : 0,waxing:true) }
    }
}
#Preview("Onboarding") { OnboardingView {}.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Onboarding • short",traits:.fixedLayout(width:375,height:647)) { OnboardingView {}.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Onboarding • landscape",traits:.landscapeLeft) { OnboardingView {}.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Onboarding • landscape • AX5",traits:.landscapeLeft) { OnboardingView {}.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
