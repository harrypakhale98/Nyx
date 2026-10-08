import AppIntents
import SwiftUI

/// Park detail offers its park and night to Handoff (another iPhone, iPad or Apple Vision Pro
/// signed in to the same Apple Account picks it up) and names the park to Siri, so "what's the
/// score here" knows the park on screen (`appEntityIdentifier`, iOS 18.2). Not offered to
/// Spotlight or Siri suggestions: nothing is indexed or predicted from what someone looks at.
struct ParkHandoffActivity: ViewModifier {
    let park: Park
    let night: Date
    func body(content: Content) -> some View {
        content.userActivity(ParkHandoff.type) { activity in
            let handoff=ParkHandoff(park:park,night:night)
            activity.title=park.shortName
            activity.userInfo=handoff.userInfo
            activity.requiredUserInfoKeys=["park"]
            activity.targetContentIdentifier=park.id
            activity.isEligibleForHandoff=true
            activity.isEligibleForSearch=false
            activity.isEligibleForPrediction=false
            activity.appEntityIdentifier=EntityIdentifier(for:ParkEntity.self,identifier:park.id)
        }
    }
}
extension View {
    /// Handoff and Siri's on-screen park for park detail (`ParkHandoffActivity`).
    func parkHandoff(_ park: Park, night: Date) -> some View { modifier(ParkHandoffActivity(park:park,night:night)) }
}
