import ActivityKit
import Foundation

struct PairingActivityAttributes:ActivityAttributes {
    struct ContentState:Codable,Hashable {
        var pin:String?
        var message:String
        var expiresAt:Date
    }
    var session:String
}
