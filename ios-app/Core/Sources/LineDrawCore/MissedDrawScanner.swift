import Foundation

public struct MissedDrawFinding:Identifiable,Sendable,Codable {
    public var id:String {activityKey}
    public let activityKey:String,product:String,store:String,status:String
    public let totalSeconds:Double,openSeconds:Double,querySeconds:Double,decisionSeconds:Double
    public let reads:Int
    public let reason:String?
    public var observations:[DeviceObservation]?=nil
}

/// Read-only verification, independent of local participation records. Never dispatches taps.
@MainActor public final class MissedDrawScanner {
    private let driver:any DeviceDriver
    private let clock:()->TimeInterval
    private let sleep:(Double)async throws->Void
    private let update:(Int,Int,MissedDrawFinding?)->Void
    public init(driver:any DeviceDriver,clock:@escaping()->TimeInterval={ProcessInfo.processInfo.systemUptime},sleep:@escaping(Double)async throws->Void={try await Task.sleep(for:.seconds($0))},update:@escaping(Int,Int,MissedDrawFinding?)->Void){
        self.driver=driver;self.clock=clock;self.sleep=sleep;self.update=update
    }
    /// Deduplicate before pagination so repeated catalog aliases cannot shift
    /// the next batch cursor or scan the same coupon across a boundary.
    public static func candidates(_ rows:[Draw],at now:Date=Date())->[Draw]{
        var seen=Set<String>()
        return rows.filter{$0.runnable(at:now) && seen.insert($0.activityKey).inserted}
    }
    public func run(_ rows:[Draw])async throws {
        let queue=Self.candidates(rows)
        update(0,queue.count,nil)
        for (index,row) in queue.enumerated() {
            try Task.checkCancellation()
            guard let url=row.canonicalURL,LinkPolicy.canonical(url)==url else{continue}
            let began=clock(),deadline=began+12
            var opened=0.0,queried=0.0,decided=0.0,reads=0,status="UNKNOWN",reason:String?
            var observations=[DeviceObservation]()
            func open()async throws->String{let start=clock();defer{opened+=clock()-start};return try await driver.open(url)}
            func snapshot()async throws->DeviceScreen{let start=clock();reads+=1;defer{queried+=clock()-start};return try await driver.scanSnapshot()}
            driver.beginScanItem(row,deadline:deadline)
            do {
                let baseline=try await open()
                while clock()<deadline {
                    try Task.checkCancellation()
                    let queryBegan=clock()
                    let screen=try await snapshot()
                    let querySeconds=clock()-queryBegan
                    func trace(_ phase:String,_ decision:ScreenDecision){
                        let code:String;var rect:ScreenRect?;var message:String?
                        switch decision {
                        case .click(let action,let node):code="click:"+action;rect=node.rect
                        case .terminal(let status):code="terminal:"+status
                        case .pause(let text):code="pause";message=text
                        case .wait:code="wait"
                        case .reopen:code="reopen"
                        }
                        observations.append(DeviceObservation(item:index+1,read:reads,elapsed:clock()-began,querySeconds:querySeconds,reason:phase,decision:code,bundle:screen.bundle,navigationReason:screen.navigationReason,lookupMode:screen.lookupMode,pending:screen.navigationPending,verified:screen.navigationVerified,sameAsBaseline:screen.navigationFingerprint==baseline,keyChanged:false,stableCount:0,nodeCount:screen.nodes.count,buttonCount:screen.nodes.filter{$0.type=="XCUIElementTypeButton" && $0.enabled}.count,targetRect:rect,nativeQuerySeconds:screen.nativeQuerySeconds,nativeMetrics:screen.nativeMetrics,decisionReason:message))
                        if observations.count>128{observations.removeFirst(observations.count-128)}
                    }
                    try Task.checkCancellation()
                    guard clock()<deadline else{reason="查詢回應超過本筆期限。";trace("deadlineAfterQuery",.wait);break}
                    if screen.bundle != DeviceScreenRules.lineBundle {
                        trace("foreignForeground",.wait)
                        if clock()-began>=2{reason="前景不是 LINE，未確認本筆狀態。";break}
                        try await sleep(0.15);continue
                    }
                    // Never treat a previous coupon left onscreen as the new activity.
                    guard !screen.navigationPending,
                          screen.navigationVerified || screen.navigationFingerprint != baseline else{reason=screen.navigationPending ? "等待換頁確認。":"畫面仍與上一筆相同。";trace(screen.navigationPending ? "navigationPending":"sameAsPreviousPage",.wait);try await sleep(0.05);continue}
                    let decisionStart=clock()
                    let decision=DeviceScreenRules.classify(screen,autoFriend:true)
                    decided+=clock()-decisionStart
                    trace("classify",decision)
                    switch decision {
                    case .click(let action,_):status=action=="ADD_FRIEND" ? "NEEDS_FRIEND":"MISSED";reason=nil
                    case .terminal(let terminal):status=terminal;reason=nil
                    case .pause(let message):status="UNKNOWN";reason=message
                    case .wait,.reopen:reason="換頁已確認，等待可辨識的抽選狀態。";try await sleep(0.05);continue
                    }
                    break
                }
                driver.endItem()
            }catch let failure as ObservationFailure where failure == .deadlineExceeded || failure == .exhausted {
                reason="畫面查詢預算已用盡，未確認狀態。"
                driver.endItem() // A bounded unreadable page is unknown, never evidence of completion.
            }catch{driver.endItem();throw error}
            let finding=MissedDrawFinding(activityKey:row.activityKey,product:row.product,store:row.store,status:status,totalSeconds:clock()-began,openSeconds:opened,querySeconds:queried,decisionSeconds:decided,reads:reads,reason:reason,observations:observations)
            update(index+1,queue.count,finding)
        }
    }
}

/// Read-only corroboration; never authorizes a lottery tap.
public enum ScanPageIdentity {
    public static func matches(_ screen:DeviceScreen,draw:Draw)->Bool{
        guard screen.bundle==DeviceScreenRules.lineBundle else{return false}
        let documents=screen.nodes.filter{$0.type=="XCUIElementTypeWebView"}.flatMap(\.labels).compactMap{LinkPolicy.canonical($0)}
        if documents.contains(where:{$0 != draw.canonicalURL}){return false}
        func compact(_ value:String)->String{value.lowercased().filter{$0.isLetter || $0.isNumber}}
        let product=draw.product.uppercased()
        guard let range=product.range(of:"^[A-Z]{1,3}-[0-9]{2,3}(?![0-9])",options:.regularExpression) else{return false}
        let sku=compact(String(product[range])),store=compact(draw.store)
        guard store.count>=5 else{return false}
        let labels=screen.nodes.filter{!$0.ocr}.flatMap(\.labels)
        // Match the SKU as a token, rather than mistaking CX-01 for CX-010.
        let token=String(product[range])
        let hasSKU=labels.contains{label in label.uppercased().range(of:"(?<![A-Z0-9])"+NSRegularExpression.escapedPattern(for:token)+"(?![0-9])",options:.regularExpression) != nil && compact(label).contains(sku)}
        return hasSKU && labels.contains{compact($0).contains(store)}
    }
}
