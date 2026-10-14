import SwiftUI

struct OnboardingView:View {
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Landscape on iPhone (and iPhone Duo's outer display turned): the art beside the words, so the
    /// words are never pushed under the page's controls.
    @Environment(\.verticalSizeClass) private var verticalSize
    private var beside:Bool { verticalSize == .compact && !typeSize.isAccessibilitySize }
    /// Compact height at any text size: Skip joins the dots and Continue in one row at the bottom and
    /// the margins tighten, so the page keeps most of the height.
    private var compactHeight:Bool { verticalSize == .compact }
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion:Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @State private var page=DebugScenario.onboardingPage
    /// The fade above the page dots grows with the text, so a large line fades out rather than being sliced.
    @ScaledMetric(relativeTo:.body) private var fade=24.0
    let finish:()->Void
    private let titles:[LocalizedStringKey]=["Where and when\nthe sky is darkest","A darker sky.\nA clearer plan.","Made for dark eyes"]
    /// The first page names the US national parks where the device is set to the United States, as it
    /// always has; anywhere else, the parks and dark-sky places of every country that Nyx now scores.
    private var messages:[LocalizedStringKey] {[
        Locale.current.region?.identifier == "US"
            ? "Nyx compares the \(model.parks.isEmpty ? 63 : model.parks.count) national parks night by night, so you know which park to drive to and which night to take off."
            : "Nyx compares national parks and dark-sky places around the world, night by night, so you know where to go and which night to take off.",
        "Moonlight, clouds, sky glow and true darkness become one score. Every estimate tells you what is still unknown.",
        "Turn the screen red at any time, here or from Control Center. Nyx has no account, no ads, no tracking. Your journal never leaves this phone.",
    ]}
    var body:some View {
        VStack(spacing:0) {
            // Tracking trails the X, so the wordmark is inset by one tracking step to sit on centre.
            if !compactHeight {
                HStack { Spacer();skip }.overlay { if !typeSize.isAccessibilitySize { Text("NYX").font(.caption).tracking(8).padding(.leading,8).accessibilityHidden(true) } }.padding(.horizontal,28).padding(.top,28)
            }
            TabView(selection:$page) {
                ForEach(0..<3,id:\.self) { index in
                    ScrollView {
                        let layout=beside ? AnyLayout(HStackLayout(spacing:36)) : AnyLayout(VStackLayout(spacing:index==1 && !typeSize.isAccessibilitySize ? 16 : 28))
                        layout {
                            art(index).frame(maxWidth:beside ? 320 : nil)
                            VStack(spacing:beside ? 16 : (index==1 && !typeSize.isAccessibilitySize ? 16 : 28)) {
                                Text(titles[index]).font(.system(beside ? .title : .largeTitle,design:.serif)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                                Text(messages[index]).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                                if index==2 { redToggle }
                            }
                        }.padding(.horizontal,compactHeight ? 20 : 28).padding(.vertical,index==1 || typeSize.isAccessibilitySize || beside ? 12 : 28).frame(maxWidth:beside ? 760 : 560).frame(maxWidth:.infinity)
                    }.scrollBounceBehavior(.basedOnSize).defaultScrollAnchor(.center,for:.alignment)
                    // Copy taller than the page shows its scroll indicator once, so "more below" is never only a fade.
                    .scrollIndicatorsFlash(onAppear:true)
                    // Copy that runs past the controls fades out instead of being cut mid-line.
                    // At compact height the fade stays short, so a large line is not lost in it.
                    .mask { VStack(spacing:0) { Color.black;LinearGradient(colors:[.black,.clear],startPoint:.top,endPoint:.bottom).frame(height:compactHeight ? min(fade,32) : fade) } }
                    .tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode:.never))
            if compactHeight {
                // Dots, Skip and Continue in one row; at the largest sizes, Continue goes under the other two.
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:20) { dots;Spacer(minLength:8);skip;proceed }
                    VStack(spacing:8) { HStack { dots;Spacer(minLength:8);skip };proceed }
                }.padding(.horizontal,20).padding(.top,4).padding(.bottom,8)
            } else {
                VStack(spacing:20) { dots;proceed }.padding(.bottom,28)
            }
        }.background(NightBackground(score:page==1 ? 94 : nil)).foregroundStyle(palette.ink)
    }
    private var skip:some View { Button("Skip") { finish() }.frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
    private var dots:some View {
        HStack(spacing:12) { ForEach(0..<3,id:\.self) { i in Capsule().fill(i==page ? palette.accent : palette.line).frame(width:i==page ? 18 : 5,height:5) } }
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
            .buttonStyle(.borderedProminent).foregroundStyle(Color.black).controlSize(.large)
    }
    private let moonSize:CGFloat=170
    /// At accessibility sizes the decorative Moon is left out, so the headline and the first lines
    /// of the message sit above the page dots rather than behind the fade.
    @ViewBuilder private func art(_ index:Int)->some View {
        switch index {
        case 0: if !typeSize.isAccessibilitySize { OnboardingMoon(daysAfterNew:3).frame(width:beside ? 130 : moonSize,height:beside ? 130 : moonSize).padding(.vertical,beside ? 8 : 24) }
        case 1: ScoreAnatomy(active:page==1)
        // The last page ends bright: a waxing gibbous Moon, which turns red with the switch below it.
        default: if !typeSize.isAccessibilitySize { OnboardingMoon(daysAfterNew:11).frame(width:beside ? 130 : moonSize,height:beside ? 130 : moonSize).padding(.vertical,beside ? 8 : 24) }
        }
    }
    /// The real night-vision switch: the whole app, this page included, turns red on the shared spring.
    private var redToggle:some View {
        Toggle(isOn:$nightVision) {
            Label { Text("Night vision") } icon:{ Image(systemName:nightVision ? "flashlight.on.circle.fill" : "flashlight.off.circle").foregroundStyle(palette.accent) }.font(.headline)
        }
        .tint(palette.controlTint)
        .padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:340,minHeight:56)
        .background(Capsule().fill(palette.panel)).overlay(Capsule().stroke(palette.line,lineWidth:0.5))
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
#Preview("Onboarding • landscape",traits:.landscapeLeft) { OnboardingView {}.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Onboarding • landscape • AX5",traits:.landscapeLeft) { OnboardingView {}.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
