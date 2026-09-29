import ActivityKit
import WidgetKit
import SwiftUI

@main struct PairingActivityWidget:Widget {
    var body:some WidgetConfiguration {
        ActivityConfiguration(for:PairingActivityAttributes.self){context in
            HStack {
                VStack(alignment:.leading,spacing:6){
                    Label("LineDraw 手機配對",systemImage:"iphone.gen3.radiowaves.left.and.right").font(.headline)
                    if !context.isStale,Date()<context.state.expiresAt,let pin=context.state.pin {
                        Text(pin).font(.largeTitle.monospacedDigit().bold()).privacySensitive()
                    }
                    Text(context.state.message).font(.caption)
                }
                Spacer()
                Text(timerInterval:Date()...max(Date(),context.state.expiresAt),countsDown:true).monospacedDigit().frame(width:48)
            }.padding().activityBackgroundTint(.black.opacity(0.85)).activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string:"linedraw://device-setup"))
        } dynamicIsland:{context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading){Label("LineDraw 配對",systemImage:"iphone.gen3")}
                DynamicIslandExpandedRegion(.center){
                    if !context.isStale,Date()<context.state.expiresAt,let pin=context.state.pin{Text(pin).font(.title.monospacedDigit().bold()).privacySensitive()}
                }
                DynamicIslandExpandedRegion(.bottom){Text(context.state.message).font(.caption)}
            } compactLeading:{Image(systemName:"iphone.gen3.radiowaves.left.and.right")}
              compactTrailing:{Image(systemName:context.state.pin == nil ? "ellipsis":"key.fill")}
              minimal:{Image(systemName:"key.fill")}
            .widgetURL(URL(string:"linedraw://device-setup"))
        }
    }
}
