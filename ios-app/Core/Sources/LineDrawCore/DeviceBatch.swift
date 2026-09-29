import Foundation

public enum DeviceDriverError:Error {case notDispatched, disconnected}
@MainActor public protocol DeviceDriver:AnyObject {
    func open(_ url:String)async throws->String
    func snapshot()async throws->DeviceScreen
    func tap(_ target:ScreenNode)async throws
    func tap(_ target:ScreenNode,observed:DeviceScreen)async throws
    func online()async->Bool
}
public extension DeviceDriver {
    func tap(_ target:ScreenNode,observed:DeviceScreen)async throws{try await tap(target)}
}
public struct DeviceBatchProgress:Sendable {
    public var state="IDLE";public var reason="尚未開始";public var index=0;public var total=0;public var round=0;public var busy=false
    public var itemStep=0
    public var workTotal:Int64{Int64(max(total,1)*6+1)}
    public var workCompleted:Int64{Int64(index*6+min(max(itemStep,0),5))}
    public init(){}
    public var locked:Bool{busy || state=="RUNNING" || state=="PAUSED"}
}
public struct DeviceItemTiming:Sendable,Codable {
    public var index:Int
    public var total:Double=0,open:Double=0,read:Double=0,tap:Double=0,save:Double=0
    public var reads:Int=0
    public var status="PENDING"
}
/// Actual completed reads count as work even while LINE is still loading.
/// The total is an estimate (12 reads per item), expanded when necessary;
/// one unit always remains for final cleanup. No timer advances this progress.
public struct DeviceWorkProgress:Sendable {
    private var milestones:Int64=0,baseTotal:Int64=1,reads:Int64=0,estimatedReads:Int64=12
    public init(){}
    public var completed:Int64{milestones+reads}
    public var total:Int64{max(baseTotal+max(estimatedReads,reads),completed+1)}
    public mutating func observed(){reads+=1}
    public mutating func update(_ progress:DeviceBatchProgress){
        milestones=max(milestones,progress.workCompleted)
        baseTotal=max(baseTotal,progress.workTotal)
        estimatedReads=max(estimatedReads,Int64(max(progress.total,1))*12)
    }
}
@MainActor public final class DeviceBatch {
    public private(set) var progress=DeviceBatchProgress()
    public private(set) var itemTimings=[DeviceItemTiming]()
    private var item=DeviceItemTiming(index:0)
    private let driver:any DeviceDriver
    private let read:(String)->ParticipationRecord?
    private let write:(Draw,ParticipationRecord?)throws->Void
    private let update:(DeviceBatchProgress)->Void
    private let fetch:(()async throws->[Draw])?
    private let sleep:(Double)async throws->Void
    private let clock:()->TimeInterval
    private var stopped=false;private var paused=false;private var skip=false
    private let expectedBundle:String
    public init(driver:any DeviceDriver,expectedBundle:String=DeviceScreenRules.lineBundle,read:@escaping(String)->ParticipationRecord?,write:@escaping(Draw,ParticipationRecord?)throws->Void,update:@escaping(DeviceBatchProgress)->Void,fetch:(()async throws->[Draw])?=nil,clock:@escaping()->TimeInterval={ProcessInfo.processInfo.systemUptime},sleep:@escaping(Double)async throws->Void={try await Task.sleep(for:.seconds($0))}){
        self.driver=driver;self.expectedBundle=expectedBundle;self.read=read;self.write=write;self.update=update;self.fetch=fetch;self.clock=clock;self.sleep=sleep
    }
    public func pause(){paused=true;progress.state="PAUSED";progress.reason="已暫停；回到 App 可繼續或停止。";publish()}
    public func resume(){guard paused,!progress.busy else{return};paused=false;progress.state="RUNNING";publish()}
    public func skipCurrent(){guard paused,!progress.busy else{return};skip=true;resume()}
    public func stop(){stopped=true;paused=false;progress.state="STOPPING";progress.reason="正在停止並保存紀錄…";publish()}
    private func publish(){update(progress)}
    private func reached(_ step:Int){if step>progress.itemStep{progress.itemStep=step;publish()}}
    private func check()throws{if stopped || Task.isCancelled{throw CancellationError()}}
    private func gate()async throws{try check();while paused{progress.busy=false;publish();try await sleep(0.25);try check()};progress.busy=true;publish()}
    private func save(_ draw:Draw,_ status:String,_ reason:String)throws{let began=clock();defer{item.save+=clock()-began};try write(draw,ParticipationRecord(id:draw.activityKey,product:draw.product,store:draw.store,status:status,evidence:reason))}
    private func open(_ url:String)async throws->String{let began=clock();defer{item.open+=clock()-began};let result=try await driver.open(url);reached(1);return result}
    private func snapshot()async throws->DeviceScreen{let began=clock();item.reads+=1;defer{item.read+=clock()-began};return try await driver.snapshot()}
    private func tap(_ node:ScreenNode,observed:DeviceScreen)async throws{let began=clock();defer{item.tap+=clock()-began};try await driver.tap(node,observed:observed)}
    private func awaitNetwork()async throws{
        let deadline=clock()+60
        while !(await driver.online()) {try check();if clock()>=deadline{throw LineDrawError.message("網路中斷超過 60 秒，請恢復網路後再開始。")};progress.reason="等待網路恢復…";publish();try await sleep(1)}
    }
    public func run(_ initial:[Draw],allInitial:[Draw],filter:CatalogFilter,autoFriend:Bool,autoContinue:Bool)async{
        guard !progress.locked else{return};stopped=false;paused=false;skip=false;itemTimings=[]
        var queue=initial;var seen=Set(allInitial.map(\.activityKey));var seenIDs=Set(allInitial.map(\.id));progress=DeviceBatchProgress();progress.state="RUNNING";progress.total=queue.count;progress.busy=true;publish()
        do{
            while true{
                while progress.index<queue.count {
                    try await gate();let row=queue[progress.index]
                    if read(row.activityKey)?.blocksRepeat != true {
                        if row.runnable(at:Date()),let url=row.canonicalURL,LinkPolicy.canonical(url)==url{try await process(row,url:url,autoFriend:autoFriend)}
                        else{try save(row,"SKIPPED","活動不在有效期間或連結未解析。")}
                    }
                    progress.index+=1;progress.itemStep=0;publish()
                }
                guard autoContinue,progress.round<3,let fetch else{break};try await gate();progress.reason="同步新活動…";publish()
                let fresh=try await fetch();try check();let next=fresh.filter{!seen.contains($0.activityKey) && !seenIDs.contains($0.id) && $0.runnable(at:Date()) && read($0.activityKey)?.blocksRepeat != true && filter.matches($0,recorded:false,now:Date())}
                seen.formUnion(fresh.map(\.activityKey));seenIDs.formUnion(fresh.map(\.id));guard !next.isEmpty else{break};queue+=next;progress.total=queue.count;progress.round+=1;publish()
            }
            progress.state="COMPLETED";progress.reason="本輪完成；已送出不代表中獎。"
        }catch is CancellationError{progress.state="STOPPED";progress.reason="已停止；不會自動重送未確認的操作。"}
        catch{progress.state="STOPPED";progress.reason=error.localizedDescription}
        progress.busy=false;publish()
    }
    private func process(_ row:Draw,url:String,autoFriend:Bool)async throws{
        let began=clock();item=DeviceItemTiming(index:progress.index+1)
        defer{item.total=clock()-began;item.status=read(row.activityKey)?.status ?? "PENDING";itemTimings.append(item)}
        var friend=false
        for attempt in 0..<2 {
            try await gate();try await awaitNetwork();try check()
            progress.reason="開啟第 \(progress.index+1) 筆\(attempt==1 ? "（重新載入）":"")";publish()
            var baseline=try await open(url)
            var deadline=clock()+30;var stable="";var stability=0;var reopened=false
            while clock()<deadline {
                try await gate();if skip{skip=false;if read(row.activityKey)==nil{try save(row,"SKIPPED","使用者略過。")};return}
                let before=clock();try await awaitNetwork();deadline+=clock()-before;try check()
                let screen=try await snapshot();try check()
                // A slow read/recovery must not authorize a tap after the load deadline.
                guard clock()<deadline else{break}
                if screen.bundle=="com.apple.springboard"{stable="";stability=0;try await sleep(0.2);continue}
                let decision=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle,autoFriend:autoFriend,friendAttempted:friend)
                if screen.navigationPending {
                    // An alert/login is actionable as a pause even during a
                    // pending navigation; an old result/button is never accepted.
                    if screen.bundle==expectedBundle,case .pause(let reason)=decision{paused=true;progress.state="PAUSED";progress.reason=reason;publish();let began=clock();try await gate();deadline+=clock()-began}
                    stable="";stability=0;try await sleep(0.1);continue
                }
                if !screen.navigationVerified,screen.navigationFingerprint==baseline{stable="";stability=0;try await sleep(0.2);continue}
                if screen.navigationVerified{reached(2)}
                let key=DeviceScreenRules.stabilityKey(screen,decision:decision)
                if key==stable{stability+=1}else{stable=key;stability=1}
                guard stability>=2 || DeviceScreenRules.allowsSingleObservation(screen,decision:decision) else{try await sleep(0.2);continue}
                switch decision {
                case .wait:break
                case .pause(let reason):paused=true;progress.state="PAUSED";progress.reason=reason;publish();let began=clock();try await gate();deadline+=clock()-began;stable="";stability=0
                case .terminal(let status):try save(row,status,"畫面顯示已參加、已結束或結果；已略過。");return
                case .reopen:
                    if !reopened{baseline=try await open(url);reopened=true;deadline=clock()+30;stable="";stability=0}
                case .click(let action,let node):
                    try check();let previous=read(row.activityKey)
                    try save(row,action+"_INTENT","已保存操作意圖，尚未確認指令回應。")
                    reached(3)
                    do {try await tap(node,observed:screen)}
                    catch DeviceDriverError.notDispatched {try write(row,previous);stable="";stability=0;try await sleep(0.2);continue}
                    catch {try save(row,"REVIEW","點擊回應不明，保留紀錄避免自動重送。");throw LineDrawError.message("本筆操作未確認，已停止。請在紀錄檢查本筆活動。")}
                    reached(4)
                    if action=="ADD_FRIEND"{try save(row,"FRIEND_ADDED","加入好友指令已回應。");friend=true;baseline=try await open(url);reopened=true;deadline=clock()+30;stable="";stability=0}
                    else{try save(row,"SUBMITTED","點擊指令成功回應，直接接續下一筆；未等待中獎結果。");reached(5);return}
                }
                try await sleep(0.2)
            }
        }
        try save(row,"LOAD_TIMEOUT","兩次載入均超過 30 秒，已接續下一筆。")
    }
}
