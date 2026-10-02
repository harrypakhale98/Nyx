import SwiftUI
import TipKit
struct ScoreTip:Tip {
    var title:Text { Text("Read the estimate") }
    var message:Text? { Text("Open the breakdown to see whether clouds are included and how moonlight shapes this night.") }
    var image:Image? { Image(systemName:"moon.stars") }
}
