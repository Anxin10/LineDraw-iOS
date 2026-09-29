import Foundation

/// A URL acknowledgement or changed result text alone cannot prove navigation.
/// Without document identity, require observing the coupon actually absent.
public struct DeviceNavigationGuard:Sendable {
    public let expectedBundle:String
    public let targetURL:String
    public private(set) var verified=false
    public init(expectedBundle:String,targetURL:String,closed:Bool=false){self.expectedBundle=expectedBundle;self.targetURL=targetURL;verified=closed}
    public mutating func observe(_ screen:DeviceScreen)->Bool {
        guard screen.bundle==expectedBundle else{return false}
        if verified{return true}
        guard !screen.nodes.contains(where:{$0.type=="XCUIElementTypeAlert"}) else{return false}
        if screen.nodes.contains(where:{$0.type=="XCUIElementTypeWebView" && $0.labels.contains(targetURL)}) {
            verified=true;return true
        }
        // A sparse predicate query, an empty/error source, or a loading WebView
        // is not evidence of dismissal. Do not confuse the old draw's result
        // transition with a new coupon, even when both pages look identical.
        guard !screen.targeted,screen.nodes.contains(where:{$0.type=="XCUIElementTypeApplication"}),
              !screen.nodes.contains(where:{$0.type=="XCUIElementTypeWebView"}) else{return false}
        // A native official-account Add Friend page is outside the coupon too.
        // Its plain 加入好友 button must remain reachable; combined draw actions
        // and WebViews are still treated as a coupon/loading document.
        let couponWords=DeviceScreenRules.couponHeaders+DeviceScreenRules.submit+DeviceScreenRules.combined+DeviceScreenRules.claimed+DeviceScreenRules.participated+DeviceScreenRules.completed+["已結束","可惜...沒有抽中！"]
        let words=Set(couponWords.map(DeviceScreenRules.normalize))
        guard !screen.nodes.flatMap(\.labels).contains(where:{words.contains(DeviceScreenRules.normalize($0))}) else{return false}
        verified=true
        return true
    }
    public mutating func confirmedClosure(){verified=true}
}

/// A close tap acknowledgement precedes UIKit dismissal completion. Wait for
/// fresh observations outside the coupon sheet before dispatching the next URL.
@MainActor public enum DeviceNavigation {
    /// Notifications can temporarily cover Close. Observe only; never dismiss
    /// an unknown app's banner or authorize a tap from a covered screenshot.
    public static func awaitHeaderExposure(
        read:()async throws->(banner:ScreenRect?,headerVisible:Bool),
        canAct:()->Bool,
        clock:()->TimeInterval={ProcessInfo.processInfo.systemUptime},
        sleep:(Double)async throws->Void={try await Task.sleep(for:.seconds($0))}
    )async throws->(banner:ScreenRect?,headerVisible:Bool) {
        let deadline=clock()+6
        while clock()<deadline {
            try Task.checkCancellation();guard canAct() else{throw CancellationError()}
            let observation=try await read()
            try Task.checkCancellation();guard canAct() else{throw CancellationError()}
            guard clock()<deadline else{break}
            if observation.banner != nil || observation.headerVisible{return observation}
            try await sleep(0.35)
        }
        throw LineDrawError.message("優惠券頂部持續被遮擋，已停止；請收起系統橫幅後再開始。")
    }
    /// Exact own-title matches are supplied by OCR. Multiple completed/current
    /// activities may share the expanded panel; swipe the first title's left
    /// side, never the right-hand task Stop control or an unrecognized banner.
    public static func progressBanner(_ matches:[ScreenRect],width:Double,height:Double)->ScreenRect? {
        matches.filter{$0.isInside(width:width,height:height) && $0.y+$0.height<=height*0.18}
            .sorted{$0.y==$1.y ? $0.x<$1.x:$0.y<$1.y}.first
    }
    public static func afterClosing(
        stillVisible:()async throws->Bool,
        canAct:()->Bool,
        clock:()->TimeInterval={ProcessInfo.processInfo.systemUptime},
        sleep:(Double)async throws->Void={try await Task.sleep(for:.seconds($0))}
    )async throws {
        let deadline=clock()+6
        var stable=0
        while clock()<deadline {
            try Task.checkCancellation();guard canAct() else{throw CancellationError()}
            let visible=try await stillVisible()
            try Task.checkCancellation();guard canAct() else{throw CancellationError()}
            guard clock()<deadline else{break}
            stable=visible ? 0:stable+1
            if stable>=2{return}
            try await sleep(0.1)
        }
        throw LineDrawError.message("上一張優惠券尚未關閉，已停止；下一筆尚未開啟。請回到 LINE 關閉優惠券後再開始。")
    }
}
