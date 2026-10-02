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
    let base:URL
    private let session:URLSession
    private var sessionID=""
    var canAct:()->Bool={true}
    private var dimensions:(width:Double,height:Double)?
    private var recentScreen:DeviceScreen?;private var recentScreenAt:TimeInterval=0
    private var recentOrientation=UIDeviceOrientation.unknown
    private var targetedLookupAvailable=true
    private var nextTargetedLookup:TimeInterval=0
    private var lookupBudget=DeviceLookupBudget()
    private var navigationGuard:DeviceNavigationGuard?
    private var lastDrawAck:TimeInterval?
    private(set) var navigationCounts=[String:Int]()
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
    func request(_ method:String,_ path:String,_ body:[String:Any]?=nil,timeout:TimeInterval=12)async throws->Any{
        let began=ProcessInfo.processInfo.systemUptime
        defer{measured(method+" "+(path.hasPrefix("session/") ? path.split(separator:"/").dropFirst(2).joined(separator:"/"):path),began)}
        try Task.checkCancellation();var r=URLRequest(url:base.appendingPathComponent(path));r.httpMethod=method;r.timeoutInterval=timeout
        #if DEBUG
        inFlightOperation=WDARequestExecutor.operation(r);onDiagnosticChange?()
        defer{inFlightOperation=nil;onDiagnosticChange?()}
        #endif
        if let body{r.httpBody=try JSONSerialization.data(withJSONObject:body);r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let bytes:Data,response:URLResponse
        do {
            (bytes,response)=try await WDARequestExecutor.execute(r,send:{request in
                #if DEBUG
                if request.httpMethod=="GET",path==self.route("source"),self.fixtureNavigated,
                   self.expectedBundle=="com.apple.mobilesafari",let fixture=self.fixtureBaseURL,
                   URL(string:fixture)?.host=="127.0.0.1",let fault=self.fixtureReadFault {
                    self.fixtureReadFault=nil
                    try await fault()
                }
                #endif
                let result=try await self.session.data(for:request)
                _=try self.decode(result.0,response:result.1,operation:WDARequestExecutor.operation(request))
                return result
            },onAttempt:{attempt in
                self.requestAttempts.append(attempt)
                if self.requestAttempts.count>200{self.requestAttempts.removeFirst(self.requestAttempts.count-200)}
            })
        }catch let error as URLError where error.code == .timedOut {
            // POST /elements is a read-only query. Its caller may fall back to
            // XML; action POST requests still stop and are never replayed.
            if method=="POST",path==route("elements"){throw error}
            if method=="GET",path==route("source"){throw LineDrawError.message("讀取手機畫面兩次仍逾時，已停止。請確認手機解鎖並稍後再試；不會自動重送點擊。")}
            throw LineDrawError.message("手機端指令逾時（\(WDARequestExecutor.operation(r))），已停止。")
        }
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
        _=try await request("POST",route("appium/settings"),["settings":["waitForIdleTimeout":0,"animationCoolOffTimeout":0,"snapshotMaxDepth":60,"shouldUseCompactResponses":false,"elementResponseAttributes":DeviceElementLookup.responseAttributes]])
        // Read initial geometry while our app is foreground. Asking LINE for
        // window/size during its first deep-link transition can stall XCTest.
        let size=try await request("GET",route("window/size")) as? [String:Double] ?? [:]
        guard let width=size["width"],let height=size["height"],width>0,height>0 else{throw LineDrawError.message("無法取得手機畫面尺寸。")}
        try await setDimensions(width,height)
    }
    func ready()async->Bool{(try? await request("GET","status")) != nil}
    func shutdown()async{if !sessionID.isEmpty{_=try? await request("DELETE","session/\(sessionID)")};var r=URLRequest(url:base.appendingPathComponent("wda/shutdown"));r.timeoutInterval=3;_=try? await session.data(for:r);sessionID="";network.cancel();session.invalidateAndCancel()}
    func active()async throws->String{let value=try await request("GET",route("wda/activeAppInfo"));return (value as? [String:Any])?["bundleId"] as? String ?? ""}
    func snapshot()async throws->DeviceScreen{
        // 深連結換頁期間保留完整原生畫面讀取；LINE 替換 WebView 時，
        // 稀疏元素查詢可能造成 WDA 連線中斷。
        var screen=try await capture(allowOCR:true,preferTargeted:navigationGuard?.verified != false)
        guard var navigation=navigationGuard else{return screen}
        let wasVerified=navigation.verified
        let ready=navigation.observe(screen)
        navigationGuard=navigation
        if ready,!wasVerified{navigationCounts["ready:"+navigation.confirmation,default:0]+=1}
        screen.navigationVerified=ready
        screen.navigationPending = !ready
        return remember(screen)
    }
    private func capture(allowOCR:Bool,forceOCR:Bool=false,preferTargeted:Bool=true)async throws->DeviceScreen {
        var useTargeted=preferTargeted && !forceOCR
        #if DEBUG
        // Preserve the existing synthetic source-timeout injection. The normal
        // fixture still exercises the fast lookup when no fault is requested.
        if fixtureReadFault != nil{useTargeted=false}
        if ProcessInfo.processInfo.arguments.contains("--full-screen-lookup") || forceFixtureOCR{useTargeted=false}
        #endif
        if useTargeted,targetedLookupAvailable,ProcessInfo.processInfo.systemUptime>=nextTargetedLookup,
           let screen=try await targetedCapture(){return remember(screen)}
        return try await fullCapture(allowOCR:allowOCR,forceOCR:forceOCR)
    }
    private func targetedCapture()async throws->DeviceScreen? {
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("capture.targeted",began)}
        let bundle=try await active()
        guard bundle==expectedBundle else{return nil}
        do {
            let queryBegan=ProcessInfo.processInfo.systemUptime
            let value=try await request("POST",route("elements"),["using":"predicate string","value":DeviceElementLookup.predicate],timeout:4)
            let screen=try DeviceElementLookup.screen(from:value,bundle:bundle)
            let querySeconds=ProcessInfo.processInfo.systemUptime-queryBegan
            try await setDimensions(screen.width,screen.height)
            // Sparse/unknown layouts need the full tree and, when appropriate,
            // bottom OCR. Avoid an extra failed fast query on every loading poll.
            if case .wait=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle) {
                nextTargetedLookup=ProcessInfo.processInfo.systemUptime+1
                return nil
            }
            lookupBudget.recordTargeted(querySeconds)
            if targetedLookupAvailable,lookupBudget.preferFull{targetedLookupAvailable=false;lookupMode="full:measured-faster"}
            return screen
        }catch is DeviceElementLookupError {
            targetedLookupAvailable=false;lookupMode="full:incomplete-targeted-response"
        }catch let error as WDAResponseFailure {
            guard error.canRetryRead || ["invalid argument","unsupported operation"].contains(error.code) else{throw error}
            lookupBudget.recordFailure();targetedLookupAvailable=false
            lookupMode=["stale element reference","no such element"].contains(error.code) ? "full:stale-targeted-response":"full:targeted-error"
        }catch let error as URLError where error.code == .timedOut {
            targetedLookupAvailable=false;lookupMode="full:targeted-timeout"
        }
        try Task.checkCancellation()
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
    private func fullCapture(allowOCR:Bool,forceOCR:Bool=false)async throws->DeviceScreen{
        let began=ProcessInfo.processInfo.systemUptime
        defer{measuredPhase("capture.full",began)}
        if dimensions==nil {
            let size=try await request("GET",route("window/size")) as? [String:Double] ?? [:]
            guard let w=size["width"],let h=size["height"],w>0,h>0 else{throw LineDrawError.message("無法取得手機畫面尺寸。")}
            try await setDimensions(w,h)
        }
        let bundle=try await active()
        let queryBegan=ProcessInfo.processInfo.systemUptime
        let xml=try await request("GET",route("source")) as? String ?? ""
        var nodes=try DeviceScreenRules.parse(xml)
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
        if allowOCR,bundle==expectedBundle,case .wait=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle),
           forceOCR || forceFixtureOCR || (now-ocrSince>=0.5 && now-lastOCR>=1),
           let raw=try? await request("GET",route("screenshot")) as? String,let bytes=Data(base64Encoded:raw){
            let ocrBegan=ProcessInfo.processInfo.systemUptime
            defer{measuredPhase("ocr.bottom",ocrBegan)}
            #if DEBUG
            if forceFixtureOCR {
                let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("fixture-ocr.png")
                try? bytes.write(to:file,options:.atomic)
            }
            #endif
            let couponContext=screen.nodes.flatMap(\.labels).contains{label in DeviceScreenRules.couponHeaders.contains{DeviceScreenRules.normalize($0)==DeviceScreenRules.normalize(label)}}
            lastOCR=now;cachedOCR=try await Self.ocr(bytes,width:width,height:height,hasCouponContext:couponContext)
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
    static func ocr(_ bytes:Data,width:Double,height:Double,hasCouponContext:Bool=false)async throws->[ScreenNode]{
        try await Task.detached(priority:.userInitiated){
            // Physically crop first: Vision boxes then refer unambiguously to
            // the crop, and retina pixels are converted to WDA logical points.
            let requestedRegion=DeviceElementLookup.bottomRegion
            guard width>0,height>0,let image=UIImage(data:bytes),image.imageOrientation == .up,let cg=image.cgImage,
                  abs((Double(cg.width)/Double(cg.height))/(width/height)-1)<0.02
            else{throw LineDrawError.message("無法取得底部抽選按鈕影像。")}
            let pixelBounds=CGRect(x:0,y:0,width:CGFloat(cg.width),height:CGFloat(cg.height))
            let cropBounds=CGRect(x:0,y:CGFloat(cg.height)*(1-requestedRegion.maxY),width:CGFloat(cg.width),height:CGFloat(cg.height)*requestedRegion.height).integral.intersection(pixelBounds)
            guard let crop=cg.cropping(to:cropBounds) else{throw LineDrawError.message("無法裁切底部抽選按鈕影像。")}
            let region=CGRect(x:0,y:1-cropBounds.maxY/CGFloat(cg.height),width:1,height:cropBounds.height/CGFloat(cg.height))
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["zh-Hant","en-US"];request.usesLanguageCorrection=false
            try VNImageRequestHandler(cgImage:crop).perform([request])
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
        navigationGuard=DeviceNavigationGuard(expectedBundle:expectedBundle,targetURL:url)
        // 直接送出下一筆網址，之前不讀結果、不查畫面、不關閉也不做 OCR。
        // 網址成功回應後，再以新的畫面觀察確認就緒。
        try await dispatchURL(url)
        try Task.checkCancellation();guard canAct() else{throw CancellationError()}
        navigationGuard?.didOpen(at:ProcessInfo.processInfo.systemUptime)
        navigationCounts["directOpen",default:0]+=1
        return "pending-navigation:"+UUID().uuidString
    }
    private func dispatchURL(_ url:String)async throws {
        guard canAct() else{throw CancellationError()}
        var payload:[String:Any]=["url":url]
        #if DEBUG
        if expectedBundle=="com.apple.mobilesafari",let fixtureBaseURL{payload=["url":fixtureBaseURL+URL(string:url)!.lastPathComponent]}
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
        if !target.ocr,let recentScreen,ProcessInfo.processInfo.systemUptime-recentScreenAt<0.75,
           recentScreen.fingerprint==observed.fingerprint,recentScreen.bundle==observed.bundle,
           recentScreen.width==observed.width,recentScreen.height==observed.height,
           recentOrientation==UIDevice.current.orientation {
            try await validatedTap(target,on:recentScreen)
        }else{
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
        guard try await active()==expectedBundle,canAct() else{throw DeviceDriverError.notDispatched}
        invalidateObservation()
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
