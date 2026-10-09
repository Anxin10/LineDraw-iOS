import Foundation
import UIKit
import Combine
import ActivityKit
import BackgroundTasks
import Darwin
import LineDrawCore
import LineDrawDeviceBridge

/// Short-lived, user-initiated pairing. No external host or USB pairing command.
@MainActor final class PhonePairing:NSObject,ObservableObject,@preconcurrency NetServiceDelegate {
    static let taskID="com.anxin10.linedraw.ios.phonePairing"
    @Published private(set) var running=false
    @Published private(set) var message="尚未開始手機配對"
    @Published private(set) var pin:String?
    @Published private(set) var expiresAt:Date?
    @Published private(set) var liveActivityAvailable=false
    var onSaved:(()->Void)?
    private var work:Task<Void,Never>?
    private var service:NetService?
    private var background:BGContinuedProcessingTask?
    private var activity:Activity<PairingActivityAttributes>?
    private var publicationError=false
    private var published=false
    private var cancellationReason:String?
    private var history:[String]=[]
    private var recordSaved=false
    private var lastCode=""
    private var outcome="notStarted"

    override init(){
        super.init()
        BGTaskScheduler.shared.register(forTaskWithIdentifier:Self.taskID,using:.main){[weak self] task in
            MainActor.assumeIsolated {
                guard let self,let task=task as? BGContinuedProcessingTask,self.running else{task.setTaskCompleted(success:false);return}
                self.background=task;task.progress.totalUnitCount=4;task.progress.completedUnitCount=0
                task.expirationHandler={[weak self,weak task] in Task{@MainActor in
                    guard let self,let task,self.background === task else{return}
                    self.cancel(reason:"iOS 已結束本次背景工作。")
                }}
            }
        }
        // A previous app process may have been terminated during setup. Do not reuse its PIN.
        let oldActivities=Activity<PairingActivityAttributes>.activities
        Task{for old in oldActivities{await old.end(nil,dismissalPolicy:.immediate)}}
    }
    func start(simulated:Bool=false){
        guard !running,UIApplication.shared.applicationState == .active else{return}
        running=true;pin=nil;publicationError=false;published=false;cancellationReason=nil;recordSaved=false;history=[];lastCode="";outcome="running"
        expiresAt=Date().addingTimeInterval(240);message="準備手機配對…"
        if simulated {
            // UI tests exercise only presentation/cancellation. No listener, credentials or PIN.
            message="等待系統配對（介面測試）";work=Task{do{try await Task.sleep(for:.seconds(240))}catch{};await self.finish(success:false,simulated:true)};return
        }
        work=Task{
            do {
                let request=BGContinuedProcessingTaskRequest(identifier:Self.taskID,title:"LineDraw 手機配對",subtitle:"等待系統配對")
                request.strategy = .fail
                if #available(iOS 27.0, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
                let bgDeadline=Date().addingTimeInterval(10)
                while background==nil {
                    try Task.checkCancellation()
                    guard Date()<bgDeadline else{throw LineDrawError.message("iOS 未提供配對背景工作，請稍後重試。")}
                    try await Task.sleep(for:.milliseconds(100))
                }
                try Task.checkCancellation()
                // Activity must be requested while in foreground, before visiting Settings.
                if ActivityAuthorizationInfo().areActivitiesEnabled {
                    activity=try? Activity.request(attributes:PairingActivityAttributes(session:UUID().uuidString),content:ActivityContent(state:.init(pin:nil,message:"到設定的開發者模式選擇「Pair with LineDraw」",expiresAt:expiresAt!),staleDate:expiresAt),pushType:nil)
                }
                liveActivityAvailable=activity != nil
                let config=String(data:try JSONSerialization.data(withJSONObject:["localAddresses":Self.localAddresses()]),encoding:.utf8)!
                let start=DeviceRuntime.consume(config.withCString{ld_pair_start($0)})
                if let error=start["error"] as? String{throw LineDrawError.message(DeviceRuntime.message(error))}
                var previous=""
                while Date()<expiresAt! {
                    try Task.checkCancellation()
                    if publicationError{throw LineDrawError.message("無法發佈手機配對服務。請在設定允許 LineDraw 使用本機網路，再重試。")}
                    let status=DeviceRuntime.consume(ld_pair_status())
                    let stage=status["stage"] as? String ?? "failed",code=status["code"] as? String ?? ""
                    lastCode=code
                    if stage != previous {
                        previous=stage;history.append(stage) // Deliberately excludes PIN, identifiers and TXT records.
                        // Bonjour remains published until finish(), including the PIN exchange.
                        // Settings can cancel the dialog if its discovered service disappears.
                        pin=nil
                        switch stage {
                        case "starting":message="正在準備配對服務…"
                        case "advertising":
                            try advertise(status)
                            message="請允許本機網路。到「設定 → 隱私權與安全性 → 開發者模式」，選擇 Pair with LineDraw。"
                        case "handshake":message="系統正在建立配對，請稍候…"
                        case "pin":
                            guard let value=status["pin"] as? String,value.count==6,value.allSatisfy({$0.isASCII && $0.isNumber}) else{throw LineDrawError.message("系統未提供有效 PIN，請重新開始。")}
                            pin=value;message="在系統配對視窗輸入此 PIN；可長按動態島查看。";background?.progress.completedUnitCount=1
                        case "verifying","connecting":message="正在透過 VPN 驗證這支手機的新配對…";background?.progress.completedUnitCount=2
                        case "complete":
                            try saveRecord();recordSaved=true;onSaved?();background?.progress.completedUnitCount=3
                            message="配對已保存，正在準備必要檔案…";await updateActivity()
                            try await DDIManager.prepare{self.message=$0}
                            message="手機配對與必要檔案已完成。請按「檢查啟動」驗證 Runner；不會抽選。"
                            history.append("filesReady");await finish(success:true,filesReady:true);return
                        case "failed","stopped":throw LineDrawError.message(Self.errorMessage(code))
                        default:throw LineDrawError.message("配對出現未知狀態，已停止。")
                        }
                        background?.updateTitle("LineDraw 手機配對",subtitle:pin.map{"PIN："+$0+"，請在設定輸入"} ?? "等待系統配對或驗證")
                        await updateActivity()
                    }
                    try await Task.sleep(for:.milliseconds(200))
                }
                throw LineDrawError.message("配對已超過 4 分鐘，已關閉服務。請重新開始。")
            }catch{
                if recordSaved {
                    message="手機配對已完成並保存；必要檔案尚未準備完成。請回到 App 按「準備必要檔案」，不需重新配對。"
                    await finish(success:true);return
                }
                outcome=error is CancellationError ? (cancellationReason == nil ? "cancelled":"systemCancelled"):"failed"
                message=cancellationReason ?? (error is CancellationError ? "配對已取消。":error.localizedDescription)
                message += recordSaved ? " 已完成的配對保留，可稍後準備檔案。":" 原有配對資料保留。"
                await finish(success:false)
            }
        }
    }
    func cancel(reason:String?=nil){cancellationReason=reason;work?.cancel();stopAdvertising();ld_pair_stop();pin=nil}
    private func advertise(_ status:[String:Any])throws{
        guard let port=status["port"] as? Int,port>0,port<=65535,let name=status["name"] as? String,let txt=status["txt"] as? [String:String] else{throw LineDrawError.message("配對服務資料不完整。")}
        let net=NetService(domain:"local.",type:"_remotepairing-pairable-host._tcp.",name:name,port:Int32(port))
        net.delegate=self;net.includesPeerToPeer=true
        net.setTXTRecord(NetService.data(fromTXTRecord:txt.mapValues{Data($0.utf8)}));service=net;net.publish()
    }
    func netServiceDidPublish(_ sender:NetService){published=true}
    func netService(_ sender:NetService,didNotPublish errorDict:[String:NSNumber]){publicationError=true}
    private func stopAdvertising(){service?.stop();service?.delegate=nil;service=nil}
    private func saveRecord()throws{
        let size=ld_pair_take_record(nil,0)
        guard size>0,size<1_000_000 else{throw LineDrawError.message("新配對未完成驗證，沒有覆蓋原本配對。")}
        var data=Data(count:size);defer{data.resetBytes(in:0..<data.count)}
        let copied=data.withUnsafeMutableBytes{ld_pair_take_record($0.bindMemory(to:UInt8.self).baseAddress,size)}
        guard copied==size else{throw LineDrawError.message("新配對資料不完整。")}
        try DeviceSecrets.save(data)
    }
    private func updateActivity()async{
        guard let expiresAt else{return}
        await activity?.update(ActivityContent(state:.init(pin:pin,message:message,expiresAt:expiresAt),staleDate:expiresAt))
    }
    private func finish(success:Bool,simulated:Bool=false,filesReady:Bool=false)async{
        stopAdvertising();if !simulated{ld_pair_stop()};pin=nil
        if let activity{await activity.end(ActivityContent(state:.init(pin:nil,message:"配對已結束",expiresAt:Date()),staleDate:Date()),dismissalPolicy:.immediate)}
        activity=nil;liveActivityAvailable=false;expiresAt=nil
        if success{background?.progress.completedUnitCount=4;outcome=filesReady ? "complete":"pairedFilesPending"}
        background?.updateTitle("LineDraw 手機配對",subtitle:success ? "配對已完成":"配對已結束")
        background?.setTaskCompleted(success:success);background=nil
        if !simulated {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.taskID)
            // Device-side evidence only: never include PIN, peer name, UDID or credentials.
            let report:[String:Any]=["schema":3,"at":ISO8601DateFormatter().string(from:Date()),"success":success,"recordSaved":recordSaved,"filesReady":filesReady,"bonjourPublished":published,"stages":history,"code":lastCode,"outcome":outcome,"message":message]
            let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("phone-pairing-report.json")
            if let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]){try? data.write(to:url,options:[.atomic,.completeFileProtection])}
        }
        if simulated{message="配對已取消，未建立連線或更動憑證。"}
        running=false;work=nil
    }
    private static func localAddresses()->[String]{
        var addresses=Set<String>(["127.0.0.1"]),head:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head)==0,let first=head else{return Array(addresses)};defer{freeifaddrs(head)}
        var next:UnsafeMutablePointer<ifaddrs>?=first
        while let item=next {
            defer{next=item.pointee.ifa_next}
            guard let addr=item.pointee.ifa_addr,addr.pointee.sa_family==UInt8(AF_INET),(item.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else{continue}
            var host=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0{addresses.insert(String(cString:host))}
        }
        return addresses.sorted()
    }
    private static func errorMessage(_ code:String)->String{
        switch code {
        case "PAIR_TIMEOUT":return "配對超過 4 分鐘，已關閉服務。請重新開始。"
        case "PAIR_SETUP_FAILED":return "系統配對未完成。請確認 PIN、手機解鎖，再重新配對。"
        case "PAIR_LISTEN_FAILED","PAIR_ACCEPT_FAILED":return "無法建立手機配對服務，請確認 Wi-Fi 與本機網路權限。"
        default:return DeviceRuntime.message(code)
        }
    }
}
