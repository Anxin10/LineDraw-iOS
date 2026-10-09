import Foundation
import Vision
import Network
import UIKit
import LineDrawCore

@MainActor final class LocalWDA:DeviceDriver {
    var expectedBundle=DeviceScreenRules.lineBundle
    #if DEBUG
    var fixtureBaseURL:String?
    var fixtureReadFault:(()async throws->Void)?
    var onDiagnosticChange:(()->Void)?
    private var fixtureNavigated=false
    private(set) var inFlightOperation:String?
    func prepareColdFixture()async throws{
        guard expectedBundle=="com.apple.mobilesafari",let fixtureBaseURL,URL(string:fixtureBaseURL)?.host=="127.0.0.1" else{throw LineDrawError.message("冷啟動測試僅限 Safari 本機測試頁。")}
        // Debug-only process restart; no tab data is removed and LINE is never targeted.
        _=try await request("POST",route("wda/apps/terminate"),["bundleId":"com.apple.mobilesafari"])
        invalidateObservation()
    }
    func saveFixtureEvidence(_ name:String)async{
        // Only the synthetic page. Evidence is excluded from diagnostics/exports.
        guard expectedBundle=="com.apple.mobilesafari",(try? await active())==expectedBundle,
              let xml=try? await request("GET",route("source")) as? String,xml.contains("LineDraw 離線") else{return}
        let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        try? Data(xml.utf8).write(to:root.appendingPathComponent("fixture-\(name).xml"),options:.atomic)
        if let raw=try? await request("GET",route("screenshot")) as? String,let data=Data(base64Encoded:raw){try? data.write(to:root.appendingPathComponent("fixture-\(name).png"),options:.atomic)}
    }
    #endif
    private var batchOwnsContext=false
    private var queryContext:QueryContext?
    private var observationPolicy=ObservationPolicy()
    private var requestInFlight=false
    private var transportUncertain=false
    private var pendingReadFailure=false
    private var visualScanReads=0
    private var scanDraw:Draw?
    private var scanOpenedAt:TimeInterval=0
    private var compactScanAvailable=true
    var scanLookupMode="xml"
    var batchLookupMode="standard"
    func beginScanItem(_ draw:Draw,deadline:TimeInterval){beginItem(deadline:deadline);scanDraw=draw}
    func beginItem(deadline:TimeInterval){batchOwnsContext=true;queryContext=QueryContext(deadline:deadline);observationPolicy=ObservationPolicy();scanDraw=nil;visualScanReads=0;invalidateObservation()}
    func endItem(){batchOwnsContext=false;queryContext=nil;scanDraw=nil;invalidateObservation()}
    private func checkContext(_ captured:QueryContext?)throws {
        try Task.checkCancellation()
        guard captured==queryContext else{throw ObservationFailure.staleObservation}
        if let captured{_=try captured.timeout(cap:1)}
    }
    private func receive(_ request:URLRequest)async throws->(Data,URLResponse){
        // Cancelling a local read does not establish that XCTest stopped working.
        // The caller poisons this session on timeout rather than stacking reads.
        try await withThrowingTaskGroup(of:(Data,URLResponse).self){group in
            group.addTask{[session] in
                let (stream,response)=try await session.bytes(for:request)
                guard response.expectedContentLength<12_000_000 else{stream.task.cancel();throw WDAResponseFailure(operation:"read",status:0,code:"response too large",remoteMessage:"")}
                var data=Data();data.reserveCapacity(64*1024)
                for try await byte in stream {
                    if data.count % 4096 == 0 {try Task.checkCancellation()}
                    guard data.count<11_999_999 else{stream.task.cancel();throw WDAResponseFailure(operation:"read",status:0,code:"response too large",remoteMessage:"")}
                    data.append(byte)
                }
                return (data,response)
            }
            group.addTask{
                try await Task.sleep(for:.seconds(request.timeoutInterval))
                throw URLError(.timedOut)
            }
            defer{group.cancelAll()}
            return try await group.next()!
        }
    }
    let base:URL
    private let session:URLSession
    private var sessionID=""
    var canAct:()->Bool={true}
    private var dimensions:(width:Double,height:Double)?
    private var recentScreen:DeviceScreen?;private var recentScreenAt:TimeInterval=0
    private var recentOrientation=UIDeviceOrientation.unknown
    private var targetedLookupAvailable=true
    private var targetedConsecutiveFailures=0
    private var nextTargetedLookup:TimeInterval=0
    private var lookupBudget=DeviceLookupBudget()
    private var navigationGuard:DeviceNavigationGuard?
    private var lastDrawAck:TimeInterval?
    private(set) var navigationCounts=[String:Int]()
    private(set) var foregroundBundles=[String:Int]()
    private(set) var lookupMode="targeted"
    private var ocrFingerprint="";private var ocrSince:TimeInterval=0;private var lastOCR:TimeInterval=0;private var cachedOCR=[ScreenNode]()
    private let network=NWPathMonitor()
    private var networkReady=false
    private(set) var timings=[String:[String:Double]]()
    private(set) var phaseTimings=[String:[String:Double]]()
    private(set) var requestAttempts=[WDARequestAttempt]()
    var onRequestFailure:((String)->Void)?
    var onObservationCompleted:(()->Void)?
    private func measured(_ name:String,_ began:TimeInterval){var v=timings[name] ?? ["count":0,"seconds":0];v["count",default:0]+=1;v["seconds",default:0]+=ProcessInfo.processInfo.systemUptime-began;timings[name]=v}
    private func measuredPhase(_ name:String,_ began:TimeInterval){var v=phaseTimings[name] ?? ["count":0,"seconds":0];v["count",default:0]+=1;v["seconds",default:0]+=ProcessInfo.processInfo.systemUptime-began;phaseTimings[name]=v}

    init(port:UInt16){base=URL(string:"http://127.0.0.1:\(port)")!;let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=12;c.timeoutIntervalForResource=24;c.requestCachePolicy = .reloadIgnoringLocalCacheData;c.connectionProxyDictionary=[:];session=URLSession(configuration:c,delegate:NoRedirect(),delegateQueue:nil);network.pathUpdateHandler={[weak self] path in Task{@MainActor in self?.networkReady=path.status == .satisfied}};network.start(queue:DispatchQueue(label:"LineDraw.network"))}
    func request(_ method:String,_ path:String,_ body:[String:Any]?=nil,timeout:TimeInterval=12,query:[URLQueryItem]=[])async throws->Any{
        guard !requestInFlight else{throw ObservationFailure.concurrentRequest}
        guard !transportUncertain else{throw DeviceDriverError.disconnected}
        let captured=queryContext
        try checkContext(captured)
        requestInFlight=true
        defer{requestInFlight=false}
        let began=ProcessInfo.processInfo.systemUptime
        defer{measured(method+" "+(path.hasPrefix("session/") ? path.split(separator:"/").dropFirst(2).joined(separator:"/"):path),began)}
        try Task.checkCancellation()
        var components=URLComponents(url:base.appendingPathComponent(path),resolvingAgainstBaseURL:false)!
        if !query.isEmpty{components.queryItems=query}
        var r=URLRequest(url:components.url!);r.httpMethod=method;r.timeoutInterval=timeout
        #if DEBUG
        inFlightOperation=WDARequestExecutor.operation(r);onDiagnosticChange?()
        defer{inFlightOperation=nil;onDiagnosticChange?()}
        #endif
        if let body{r.httpBody=try JSONSerialization.data(withJSONObject:body);r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let bytes:Data,response:URLResponse
        do {
            (bytes,response)=try await WDARequestExecutor.execute(r,context:captured,send:{request in
                #if DEBUG
                if request.httpMethod=="GET",path==self.route("source"),self.fixtureNavigated,
                   self.expectedBundle=="com.apple.mobilesafari",let fixture=self.fixtureBaseURL,
                   URL(string:fixture)?.host=="127.0.0.1",let fault=self.fixtureReadFault {
                    self.fixtureReadFault=nil
                    try await fault()
                }
                #endif
                let result=try await self.receive(request)
                _=try self.decode(result.0,response:result.1,operation:WDARequestExecutor.operation(request))
                return result
            },onAttempt:{attempt in
                self.requestAttempts.append(attempt)
                if self.requestAttempts.count>200{self.requestAttempts.removeFirst(self.requestAttempts.count-200)}
            })
        }catch let error as URLError where error.code == .timedOut {
            transportUncertain=true
            throw LineDrawError.message("手機查詢逾時，遠端狀態未確認，已停止本輪；不會疊加查詢或重送點擊。")
        }catch is CancellationError {
            transportUncertain=true
            throw CancellationError()
        }
        try checkContext(captured)
        let value=try WDAResponse.decode(bytes,response:response,operation:WDARequestExecutor.operation(r))
        if method=="GET" || (method=="POST" && path==route("elements")){onObservationCompleted?()}
        return value
    }
    private func decode(_ bytes:Data,response:URLResponse,operation:String)throws->Any {
        do{return try WDAResponse.decode(bytes,response:response,operation:operation)}
        catch let error as WDAResponseFailure {
            onRequestFailure?(error.localizedDescription)
            #if DEBUG
            // Private bounded error metadata only: never save successful XML/screenshots or request bodies.
            let info:[String:Any]=["operation":error.operation,"status":error.status,"code":error.code,"message":String(error.remoteMessage.prefix(1500)),"bytes":bytes.count,"at":WireJSON.date(Date())]
            let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("wda-error.json")
            if let data=try? JSONSerialization.data(withJSONObject:info){try? data.write(to:file,options:.atomic)}
            #endif
            throw error
        }
    }
    func route(_ suffix:String)->String{"session/\(sessionID)/"+suffix}
    func connect()async throws{
        let value=try await request("POST","session",["capabilities":["alwaysMatch":["shouldWaitForQuiescence":false,"shouldUseTestManagerForVisibilityDetection":false]]])
        guard let id=(value as? [String:Any])?["sessionId"] as? String,!id.isEmpty else{throw LineDrawError.message("WDA 沒有建立工作階段。")};sessionID=id
        _=try await request("POST",route("appium/settings"),["settings":["waitForIdleTimeout":0,"animationCoolOffTimeout":0,"snapshotMaxDepth":50,"shouldUseCompactResponses":false,"elementResponseAttributes":DeviceElementLookup.responseAttributes]])
        // Read initial geometry while our app is foreground. Asking LINE for
        // window/size during its first deep-link transition can stall XCTest.
        let size=try await request("GET",route("window/size")) as? [String:Double] ?? [:]
        guard let width=size["width"],let height=size["height"],width>0,height>0 else{throw LineDrawError.message("無法取得手機畫面尺寸。")}
        try await setDimensions(width,height)
    }
    func ready()async->Bool{(try? await request("GET","status")) != nil}
    func shutdown()async{queryContext=nil;if !sessionID.isEmpty{_=try? await request("DELETE","session/\(sessionID)")};var r=URLRequest(url:base.appendingPathComponent("wda/shutdown"));r.timeoutInterval=3;_=try? await session.data(for:r);sessionID="";network.cancel();session.invalidateAndCancel()}
    func active()async throws->String{
        // The local Runner resolves the foreground host from active applications
        // without a full snapshot. Always check afresh before dispatching.
        let value=try await request("GET",route("wda/activeAppInfo"),timeout:3)
        let bundle=(value as? [String:Any])?["bundleId"] as? String ?? ""
        foregroundBundles[bundle,default:0]+=1
        return bundle
    }
    /// Read-only scanner: XML first, bypassing costly repeated element searches.
    /// Screenshot/OCR remains the fallback when native text is unavailable.
    func scanSnapshot()async throws->DeviceScreen{
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--scan-visual"){return try await visualScanSnapshot()}
        #endif
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("scan.query",began)}
        let captured=queryContext
        try checkContext(captured)
        var bundle:String
        // The read-only path already checks foreground bundle and known geometry.
        // LINE's XML can omit the visible Application root during navigation.
        var screen:DeviceScreen
        var mode=scanLookupMode
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--scan-json"){mode="json"}
        if ProcessInfo.processInfo.arguments.contains("--scan-compact"){mode="compact"}
        #endif
        if mode=="compact",!compactScanAvailable{mode="xml"}
        do {
            if mode=="compact",compactScanAvailable {
                do {screen=try await compactCapture();bundle=screen.bundle}
                catch let error as WDAResponseFailure where error.status==404 && error.code != "invalid session id" {
                    compactScanAvailable=false;return try await scanSnapshot()
                }
            }else{
                bundle=try await active()
                if mode=="json"{screen=try await jsonCapture(bundle:bundle)}
                else{screen=try await fullCapture(allowOCR:true,bundle:bundle,requireApplication:false)}
            }
        }
        catch ObservationFailure.invalidXML{return try await snapshot()}
        catch let error as WDAResponseFailure where error.canRetryRead{return try await snapshot()}
        try checkContext(captured)
        if let scanDraw,ProcessInfo.processInfo.systemUptime-scanOpenedAt>=0.5,
           ScanPageIdentity.matches(screen,draw:scanDraw) {
            switch DeviceScreenRules.classify(screen,expectedBundle:expectedBundle){
            case .click,.terminal:
                screen.navigationVerified=true;screen.navigationPending=false
                navigationCounts["scan:identity",default:0]+=1
                lookupMode="scan:"+mode+"-identity"
                return screen
            default:break
            }
        }
        if var navigation=navigationGuard {
            screen.navigationVerified=navigation.observe(screen)
            screen.navigationPending = !screen.navigationVerified
            navigationGuard=navigation
        }
        lookupMode="scan:"+(mode=="compact" && !compactScanAvailable ? "xml-fallback":mode)
        return screen
    }
    private func compactCapture(decisionOnly:Bool=false)async throws->DeviceScreen{
        guard let dims=dimensions else{throw ObservationFailure.invalidXML}
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("capture.compact",began)}
        var query=[URLQueryItem(name:"expected_bundle",value:expectedBundle)]
        if decisionOnly {
            let filter=["labels":DeviceScreenRules.observationLabels.map(DeviceScreenRules.normalize),"blockers":DeviceScreenRules.blockers.map{DeviceScreenRules.normalize($0).lowercased()}]
            let bytes=try JSONSerialization.data(withJSONObject:filter)
            query.append(URLQueryItem(name:"decision_filter",value:String(decoding:bytes,as:UTF8.self)))
        }
        let value=try await request("GET",route("linedraw/observe"),query:query)
        guard let envelope=value as? [String:Any],envelope["schema"] as? Int==1,let bundle=envelope["bundleId"] as? String else{throw ObservationFailure.invalidXML}
        foregroundBundles[bundle,default:0]+=1
        guard bundle==expectedBundle,envelope["ready"] as? Bool==true else{return DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:[])}
        guard let tree=envelope["tree"] as? [String:Any] else{throw ObservationFailure.invalidXML}
        let bytes=try JSONSerialization.data(withJSONObject:tree)
        let captured=queryContext
        let task=Task.detached(priority:.userInitiated){try JSONScreenParser.parse(bytes)}
        let nodes=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
        try checkContext(captured)
        var screen=DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:nodes)
        if let seconds=envelope["nativeSeconds"] as? Double,seconds.isFinite,seconds>=0{screen.nativeQuerySeconds=seconds}
        var metrics=[String:Double]()
        for key in ["snapshotSeconds","collectSeconds","visibilityChecks","geometrySkipped"] {
            if let value=envelope[key] as? Double,value.isFinite,value>=0{metrics[key]=value}
        }
        if !metrics.isEmpty{screen.nativeMetrics=metrics}
        return screen
    }
    private func jsonCapture(bundle:String)async throws->DeviceScreen{
        guard let dims=dimensions else{throw ObservationFailure.invalidXML}
        guard bundle==expectedBundle else{return DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:[])}
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("capture.json",began)}
        let value=try await request("GET",route("source"),query:[URLQueryItem(name:"format",value:"json"),URLQueryItem(name:"excluded_attributes",value:"focused,frame,nativeFrame,nativeAccessibilityElement,traits,minValue,maxValue,placeholderValue")])
        let bytes=try JSONSerialization.data(withJSONObject:value)
        let captured=queryContext
        let parseTask=Task.detached(priority:.userInitiated){try JSONScreenParser.parse(bytes)}
        let nodes=try await withTaskCancellationHandler(operation:{try await parseTask.value},onCancel:{parseTask.cancel()})
        try checkContext(captured)
        return DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:nodes)
    }
    /// Diagnostic candidate retained for comparison; not the default scanner.
    private func visualScanSnapshot()async throws->DeviceScreen{
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("scan.visual",began)}
        let captured=queryContext
        try checkContext(captured)
        let bundle=try await active()
        guard bundle==expectedBundle,let dims=dimensions else{return try await snapshot()}
        visualScanReads+=1
        let raw=try await request("GET",route("screenshot")) as? String ?? ""
        guard let bytes=Data(base64Encoded:raw) else{throw LineDrawError.message("截圖格式無效。")}
        let ocrBegan=ProcessInfo.processInfo.systemUptime
        let nodes=try await Self.ocr(bytes,width:dims.width,height:dims.height,bottomFraction:0.18,maxPixelWidth:640)
        measuredPhase("scan.bottomOCR",ocrBegan)
        try checkContext(captured)
        var screen=DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:nodes)
        switch DeviceScreenRules.classify(screen,expectedBundle:expectedBundle){
        case .click,.terminal:break
        default:
            // Give two screenshots a chance during loading; unfamiliar pages
            // then fall back to native checks for alerts, login and friend state.
            if visualScanReads>=3{return try await snapshot()}
        }
        if var navigation=navigationGuard {
            screen.navigationVerified=navigation.observe(screen)
            screen.navigationPending = !screen.navigationVerified
            navigationGuard=navigation
        }
        lookupMode="scan:screenshot-bottom18"
        return screen
    }
    func snapshot()async throws->DeviceScreen{
        // Observe the new page with a bounded targeted lookup first.
        var screen:DeviceScreen
        var useCompact=batchLookupMode=="compact"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--batch-compact"){useCompact=true}
        #endif
        // Keep normal navigation proof; SKU/store never authorize a batch tap.
        if useCompact,compactScanAvailable {
            do {screen=try await compactCapture(decisionOnly:true);lookupMode="batch:compact"}
            catch let error as WDAResponseFailure where error.status==404 && error.code != "invalid session id" {
                compactScanAvailable=false
                screen=try await capture(allowOCR:true,preferTargeted:true)
            }
        }else{screen=try await capture(allowOCR:true,preferTargeted:true)}
        guard var navigation=navigationGuard else{return screen}
        let wasVerified=navigation.verified
        let ready=navigation.observe(screen)
        navigationGuard=navigation
        if ready,!wasVerified{navigationCounts["ready:"+navigation.confirmation,default:0]+=1}
        screen.navigationVerified=ready
        screen.navigationPending = !ready
        screen.navigationReason=navigation.observationReason
        screen.lookupMode=lookupMode
        return remember(screen)
    }
    private func capture(allowOCR:Bool,forceOCR:Bool=false,preferTargeted:Bool=true)async throws->DeviceScreen {
        let captured=queryContext
        try checkContext(captured)
        let bundle=try await active()
        let checkedAt=ProcessInfo.processInfo.systemUptime
        if bundle != expectedBundle,let dims=dimensions {
            // No useful coupon evidence can be obtained from a foreign app.
            // Keep navigation pending without paying for its complete XML tree.
            navigationCounts["foreignObservationSkipped",default:0]+=1
            return remember(DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:[]))
        }
        var useTargeted=preferTargeted && !forceOCR
        #if DEBUG
        // Preserve the existing synthetic source-timeout injection. The normal
        // fixture still exercises the fast lookup when no fault is requested.
        if fixtureReadFault != nil{useTargeted=false}
        if ProcessInfo.processInfo.arguments.contains("--full-screen-lookup") || forceFixtureOCR{useTargeted=false}
        #endif
        if useTargeted,targetedLookupAvailable,observationPolicy.canTarget,!observationPolicy.shouldUseXML,
           ProcessInfo.processInfo.systemUptime>=nextTargetedLookup,
           let screen=try await targetedCapture(bundle:bundle){try checkContext(captured);return remember(screen)}
        if let captured,try captured.timeout(cap:4)<1{throw ObservationFailure.deadlineExceeded}
        try observationPolicy.consume(.xml)
        let freshBundle:String
        if ProcessInfo.processInfo.systemUptime-checkedAt<=0.5{freshBundle=bundle}
        else{freshBundle=try await active()}
        return try await fullCapture(allowOCR:allowOCR,forceOCR:forceOCR,bundle:freshBundle)
    }
    private func targetedCapture(bundle:String)async throws->DeviceScreen? {
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("capture.targeted",began)}
        guard bundle==expectedBundle else{return nil}
        try observationPolicy.consume(.targeted)
        do {
            let queryBegan=ProcessInfo.processInfo.systemUptime
            let value=try await request("POST",route("elements"),["using":"predicate string","value":DeviceElementLookup.predicate],timeout:12)
            let screen=try DeviceElementLookup.screen(from:value,bundle:bundle)
            let querySeconds=ProcessInfo.processInfo.systemUptime-queryBegan
            try await setDimensions(screen.width,screen.height)
            lookupBudget.recordTargeted(querySeconds)
            targetedConsecutiveFailures=0
            if case .wait=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle){
                observationPolicy.recordIncomplete()
            }else{observationPolicy.recordComplete()}
            if pendingReadFailure{navigationCounts["readRecovered",default:0]+=1;pendingReadFailure=false}
            if targetedLookupAvailable,lookupBudget.preferFull{targetedLookupAvailable=false;lookupMode="full:measured-faster"}
            return screen
        }catch is DeviceElementLookupError {
            targetedConsecutiveFailures+=1
            lookupMode="targeted:transient-incomplete"
        }catch let error as WDAResponseFailure {
            if ["invalid argument","unsupported operation"].contains(error.code) {
                lookupBudget.recordFailure();targetedLookupAvailable=false
                lookupMode="full:targeted-unsupported"
                return nil
            }
            guard error.canRetryRead else{throw error}
            targetedConsecutiveFailures+=1
            lookupMode=["stale element reference","no such element"].contains(error.code) ? "targeted:stale-element":"targeted:error"
        }catch let error as URLError where error.code == .timedOut {
            targetedConsecutiveFailures+=1
            lookupMode="targeted:timeout"
        }
        try Task.checkCancellation()
        observationPolicy.recordIncomplete();pendingReadFailure=true
        // 頁面載入過渡期（例如 DOM 替換或短暫空白）不直接 fallback 到耗時 10-15 秒的完整 XML。
        // 回傳暫態等待畫面，讓批次在 0.05-0.1 秒後能以輕量 targeted 重新查詢。
        if !observationPolicy.shouldUseXML,let dims=dimensions {
            return DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:[],targeted:true)
        }
        return nil
    }
    @discardableResult private func remember(_ screen:DeviceScreen)->DeviceScreen {
        recentScreen=screen;recentScreenAt=ProcessInfo.processInfo.systemUptime
        recentOrientation=UIDevice.current.orientation
        return screen
    }
    private func invalidateObservation(){recentScreen=nil;cachedOCR=[];ocrFingerprint="";lastOCR=0;ocrSince=0}
    private var forceFixtureOCR:Bool {
        #if DEBUG
        return expectedBundle=="com.apple.mobilesafari" && fixtureBaseURL.flatMap(URL.init(string:))?.host=="127.0.0.1" && ProcessInfo.processInfo.arguments.contains("--bottom-ocr-fixture")
        #else
        return false
        #endif
    }
    private func fullCapture(allowOCR:Bool,forceOCR:Bool=false,bundle:String,requireApplication:Bool=true)async throws->DeviceScreen{
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("capture.full",began)}
        if dimensions==nil {
            let size=try await request("GET",route("window/size")) as? [String:Double] ?? [:]
            guard let w=size["width"],let h=size["height"],w>0,h>0 else{throw LineDrawError.message("無法取得手機畫面尺寸。")}
            try await setDimensions(w,h)
        }
        if bundle != expectedBundle,let dims=dimensions {
            return remember(DeviceScreen(bundle:bundle,width:dims.width,height:dims.height,nodes:[]))
        }
        let queryBegan=ProcessInfo.processInfo.systemUptime
        let xml=try await request("GET",route("source"),timeout:12) as? String ?? ""
        let parseBegan=ProcessInfo.processInfo.systemUptime
        let captured=queryContext
        let parseTask=Task.detached(priority:.userInitiated){
            try XMLScreenParser.parse(xml,requireApplication:requireApplication,cancelled:{Task.isCancelled})
        }
        var nodes=try await withTaskCancellationHandler(operation:{try await parseTask.value},onCancel:{parseTask.cancel()})
        try checkContext(captured)
        measuredPhase("xml.parse",parseBegan)
        if pendingReadFailure{navigationCounts["readRecovered",default:0]+=1;pendingReadFailure=false}
        let querySeconds=ProcessInfo.processInfo.systemUptime-queryBegan
        if forceFixtureOCR {
            // Synthetic localhost fixture only. Hide AX draw labels so the
            // production cropped-image path must locate the real rendered text.
            let actions=Set(DeviceScreenRules.actions.map(DeviceScreenRules.normalize))
            nodes.removeAll{$0.labels.contains{actions.contains(DeviceScreenRules.normalize($0))}}
        }
        // The fresh application rectangle follows rotations; no repeated window/settings round trips.
        if let app=nodes.first(where:{$0.type=="XCUIElementTypeApplication"}),app.rect.width>0,app.rect.height>0,
           dimensions!.width != app.rect.width || dimensions!.height != app.rect.height {try await setDimensions(app.rect.width,app.rect.height)}
        let (width,height)=dimensions!
        var screen=DeviceScreen(bundle:bundle,width:width,height:height,nodes:nodes)
        if bundle==expectedBundle,!forceFixtureOCR {
            switch DeviceScreenRules.classify(screen,expectedBundle:expectedBundle) {
            case .click,.terminal:
                lookupBudget.recordFull(querySeconds)
                if targetedLookupAvailable,lookupBudget.preferFull{targetedLookupAvailable=false;lookupMode="full:measured-faster"}
            default:break
            }
        }
        let now=ProcessInfo.processInfo.systemUptime
        if screen.fingerprint != ocrFingerprint{ocrFingerprint=screen.fingerprint;ocrSince=now;cachedOCR=[]}
        if forceOCR || forceFixtureOCR{cachedOCR=[];lastOCR=0}
        // Keep the tested 40% crop until narrow-crop device validation passes.
        if allowOCR,bundle==expectedBundle,case .wait=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle),
           observationPolicy.ocr<2,
           (queryContext?.deadline ?? .infinity)-ProcessInfo.processInfo.systemUptime>=1,
           forceOCR || forceFixtureOCR || (now-ocrSince>=0.5 && now-lastOCR>=1),
           let raw=try await request("GET",route("screenshot")) as? String,let bytes=Data(base64Encoded:raw){
            try observationPolicy.consume(.ocr)
            let ocrBegan=ProcessInfo.processInfo.systemUptime
            defer{measuredPhase("ocr.bottom",ocrBegan)}
            #if DEBUG
            if forceFixtureOCR {
                let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("fixture-ocr.png")
                try? bytes.write(to:file,options:.atomic)
            }
            #endif
            let couponContext=screen.nodes.flatMap(\.labels).contains{label in DeviceScreenRules.couponHeaders.contains{DeviceScreenRules.normalize($0)==DeviceScreenRules.normalize(label)}}
            let captured=queryContext
            let results=try await Self.ocr(bytes,width:width,height:height,hasCouponContext:couponContext)
            try checkContext(captured)
            lastOCR=ProcessInfo.processInfo.systemUptime;cachedOCR=results
        }
        if allowOCR,bundle==expectedBundle,case .wait=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle),now-lastOCR<1 {
            screen.nodes+=cachedOCR
        }
        return remember(screen)
    }
    private func setDimensions(_ w:Double,_ h:Double)async throws{
        guard dimensions?.width != w || dimensions?.height != h else{return}
        _=try await request("POST",route("appium/settings"),["settings":["activeAppDetectionPoint":"\(w/2),\(h/2)"]])
        invalidateObservation()
        dimensions=(w,h)
    }
    static func ocr(_ bytes:Data,width:Double,height:Double,hasCouponContext:Bool=false,bottomFraction:Double=0.40,maxPixelWidth:Int?=nil)async throws->[ScreenNode]{
        try await Task.detached(priority:.userInitiated){
            // Physically crop first: Vision boxes then refer unambiguously to
            // the crop, and retina pixels are converted to WDA logical points.
            let requestedRegion=CGRect(x:0,y:0,width:1,height:bottomFraction)
            guard width>0,height>0,let image=UIImage(data:bytes),image.imageOrientation == .up,let cg=image.cgImage,
                  abs((Double(cg.width)/Double(cg.height))/(width/height)-1)<0.02
            else{throw LineDrawError.message("無法取得底部抽選按鈕影像。")}
            let pixelBounds=CGRect(x:0,y:0,width:CGFloat(cg.width),height:CGFloat(cg.height))
            let cropBounds=CGRect(x:0,y:CGFloat(cg.height)*(1-requestedRegion.maxY),width:CGFloat(cg.width),height:CGFloat(cg.height)*requestedRegion.height).integral.intersection(pixelBounds)
            guard let crop=cg.cropping(to:cropBounds) else{throw LineDrawError.message("無法裁切底部抽選按鈕影像。")}
            let region=CGRect(x:0,y:1-cropBounds.maxY/CGFloat(cg.height),width:1,height:cropBounds.height/CGFloat(cg.height))
            var ocrImage=crop
            if let maxPixelWidth,crop.width>maxPixelWidth {
                let scaledHeight=max(1,Int(Double(crop.height)*Double(maxPixelWidth)/Double(crop.width)))
                if let context=CGContext(data:nil,width:maxPixelWidth,height:scaledHeight,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue){
                    context.interpolationQuality = .high
                    context.draw(crop,in:CGRect(x:0,y:0,width:maxPixelWidth,height:scaledHeight))
                    if let scaled=context.makeImage(){ocrImage=scaled}
                }
            }
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["zh-Hant","en-US"];request.usesLanguageCorrection=false
            try VNImageRequestHandler(cgImage:ocrImage).perform([request])
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--bottom-ocr-fixture") {
                let rows=(request.results ?? []).compactMap{observation->[String:Any]? in
                    guard let text=observation.topCandidates(1).first else{return nil}
                    let r=ScreenRect.fromVision(observation.boundingBox,region:region,width:width,height:height)
                    return ["text":text.string,"confidence":text.confidence,"x":r.x,"y":r.y,"width":r.width,"height":r.height]
                }
                let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("fixture-ocr-observations.json")
                if let data=try? JSONSerialization.data(withJSONObject:rows){try? data.write(to:file,options:.atomic)}
            }
            #endif
            return (request.results ?? []).compactMap{observation in
                guard let text=observation.topCandidates(1).first,DeviceScreenRules.acceptsOCR(text.string,confidence:text.confidence,hasCouponContext:hasCouponContext) else{return nil}
                let r=ScreenRect.fromVision(observation.boundingBox,region:region,width:width,height:height)
                guard r.isInside(width:width,height:height),r.y>=height*0.60 else{return nil};return ScreenNode(type:"OCR",labels:[text.string],rect:r,ocr:true)
            }
        }.value
    }
    func open(_ url:String)async throws->String{
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("navigation.open",began)}
        guard LinkPolicy.canonical(url)==url else{throw LineDrawError.message("只支援已解析的 LINE 優惠券網址。")}
        guard canAct() else{throw CancellationError()}
        if batchOwnsContext,let context=queryContext{_=try context.timeout(cap:1);queryContext=context.navigating()}
        else{queryContext=QueryContext(deadline:ProcessInfo.processInfo.systemUptime+30);observationPolicy=ObservationPolicy()}
        navigationGuard=DeviceNavigationGuard(expectedBundle:expectedBundle,targetURL:url)
        // 直接送出下一筆網址，之前不讀結果、不查畫面、不關閉也不做 OCR。
        // 網址成功回應後，再以新的畫面觀察確認就緒。
        try await dispatchURL(url)
        try Task.checkCancellation();guard canAct() else{throw CancellationError()}
        navigationGuard?.didOpen(at:ProcessInfo.processInfo.systemUptime)
        scanOpenedAt=ProcessInfo.processInfo.systemUptime
        navigationCounts["directOpen",default:0]+=1
        // 修復 A：新頁面可能有不同 DOM 結構，重新嘗試 targeted lookup
        targetedLookupAvailable=true;lookupBudget=DeviceLookupBudget()
        targetedConsecutiveFailures=0
        return "pending-navigation:"+UUID().uuidString
    }
    private func dispatchURL(_ url:String)async throws {
        guard canAct() else{throw CancellationError()}
        var payload:[String:Any]=["url":url]
        #if DEBUG
        if expectedBundle=="com.apple.mobilesafari",let fixtureBaseURL{payload=["url":fixtureBaseURL+URL(string:url)!.lastPathComponent,"bundleId":expectedBundle]}
        #endif
        invalidateObservation();nextTargetedLookup=0
        if let ack=lastDrawAck{measuredPhase("handoff.ackToNextURL",ack);lastDrawAck=nil}
        _=try await request("POST",route("url"),payload)
        #if DEBUG
        if expectedBundle=="com.apple.mobilesafari",let fixtureBaseURL,URL(string:fixtureBaseURL)?.host=="127.0.0.1"{fixtureNavigated=true}
        #endif
    }
    func tap(_ target:ScreenNode)async throws{
        guard canAct() else{throw DeviceDriverError.notDispatched}
        let screen=try await capture(allowOCR:true,forceOCR:target.ocr)
        try await validatedTap(target,on:screen)
    }
    func tap(_ target:ScreenNode,observed:DeviceScreen)async throws{
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("tap.validateAndDispatch",began)}
        // One verified native observation is reusable through the short durable
        // intent write. OCR, rotation, actions and aged observations reread.
        if !target.ocr,let recentScreen,ProcessInfo.processInfo.systemUptime-recentScreenAt<1.5,
           recentScreen.fingerprint==observed.fingerprint,recentScreen.bundle==observed.bundle,
           recentScreen.width==observed.width,recentScreen.height==observed.height,
           recentOrientation==UIDevice.current.orientation {
            navigationCounts["tapObservationReused",default:0]+=1
            try await validatedTap(target,on:recentScreen)
        }else{
            let reason=target.ocr ? "ocr" : recentOrientation != UIDevice.current.orientation ? "rotation" : ProcessInfo.processInfo.systemUptime-recentScreenAt>=1.5 ? "expired" : "changed"
            navigationCounts["tapReread:"+reason,default:0]+=1
            let fresh=try await capture(allowOCR:true,forceOCR:target.ocr,preferTargeted:observed.targeted)
            guard fresh.width==observed.width,fresh.height==observed.height else{throw DeviceDriverError.notDispatched}
            try await validatedTap(target,on:fresh)
        }
    }
    private func validatedTap(_ target:ScreenNode,on screen:DeviceScreen)async throws{
        guard canAct() else{throw DeviceDriverError.notDispatched}
        guard screen.bundle==expectedBundle,target.rect.isInside(width:screen.width,height:screen.height),!screen.nodes.contains(where:{$0.type=="XCUIElementTypeAlert"}) else{throw DeviceDriverError.notDispatched}
        guard case .click(_,let fresh)=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle),fresh.rect.near(target.rect),fresh.labels.contains(where:{target.labels.map(DeviceScreenRules.normalize).contains(DeviceScreenRules.normalize($0))}) else{throw DeviceDriverError.notDispatched}
        let matches=screen.nodes.filter{$0.type==target.type && $0.enabled && $0.rect.near(target.rect) && $0.labels.contains(where:{target.labels.contains($0)})}
        guard matches.count==1,canAct() else{throw DeviceDriverError.notDispatched}
        // Revalidated exact target; never blind fixed coordinates or coupon redemption.
        let foregroundBegan=ProcessInfo.processInfo.systemUptime
        let foreground=try await active()
        measuredPhase("tap.foreground",foregroundBegan)
        guard foreground==expectedBundle,canAct() else{throw DeviceDriverError.notDispatched}
        invalidateObservation()
        let dispatchBegan=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("tap.dispatch",dispatchBegan)}
        _=try await request("POST",route("wda/tap"),["x":target.rect.x+target.rect.width/2,"y":target.rect.y+target.rect.height/2])
        lastDrawAck=ProcessInfo.processInfo.systemUptime
    }
    // Path availability is relevant to LINE. A HEAD to the catalog host on every
    // poll used to serialize unrelated Internet requests with screen inspection.
    func online()async->Bool{networkReady}

}
private final class NoRedirect:NSObject,URLSessionTaskDelegate{
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}
