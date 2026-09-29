import Foundation
import UIKit
import Security
import BackgroundTasks
import LineDrawCore
import LineDrawDeviceBridge

@MainActor final class DeviceRuntime {
    static let runner="com.beybladehunter.linedraw.DeviceRunner.xctrunner"
    static let taskID="com.beybladehunter.linedraw.ios.deviceBatch"
    private var background:BGContinuedProcessingTask?
    private var requested=false
    private var expired=false
    private var userCancelled=false
    private var work=DeviceWorkProgress()
    private var lastWorkPublish:TimeInterval=0
    private(set) var lastCode="NOT_STARTED"
    var cancellationSource:String {expired ? "backgroundTask":userCancelled ? "appStop":"taskCancellation"}
    var cancellationMessage:String {expired ? "iOS 背景工作已結束，已停止；可能由系統或系統工作進度取消。":userCancelled ? "已依使用者操作停止。":"執行已取消。"}
    func noteUserCancellation(){userCancelled=true}
    var onExpired:(()->Void)?
    private(set) var driver:LocalWDA?
    init(){
        BGTaskScheduler.shared.register(forTaskWithIdentifier:Self.taskID,using:.main){[weak self] task in
            MainActor.assumeIsolated {
                guard let self,let task=task as? BGContinuedProcessingTask,self.requested else{task.setTaskCompleted(success:false);return}
                self.background=task;task.progress.totalUnitCount=100;task.progress.completedUnitCount=0
                task.expirationHandler={[weak self,weak task] in Task{@MainActor in
                    guard let self,let task,self.background === task else{return}
                    self.expire()
                }}
            }
        }
    }
    private func expire(){expired=true;lastCode="BACKGROUND_TASK_ENDED";onExpired?();ld_stop();background?.setTaskCompleted(success:false);background=nil}
    func start(onStage:@escaping(String)->Void)async throws->LocalWDA{
        guard UIApplication.shared.applicationState == .active else{throw LineDrawError.message("請回到 App 按下開始。")}
        guard let bytes=try DeviceSecrets.load() else{throw LineDrawError.message("請先在「手機自主模式」完成手機配對。")}
        expired=false;userCancelled=false;work=DeviceWorkProgress();lastWorkPublish=0;lastCode="PREPARING";requested=true
        let request=BGContinuedProcessingTaskRequest(identifier:Self.taskID,title:"LineDraw 抽選",subtitle:"準備手機自主執行")
        request.strategy = .fail
        do{
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            let deadline=Date().addingTimeInterval(10)
            while background==nil {try Task.checkCancellation();guard Date()<deadline,!expired else{throw LineDrawError.message("iOS 尚未允許本次背景工作，請稍後再試。")};try await Task.sleep(for:.milliseconds(100))}
            try await DDIManager.prepare(onStage:onStage)
            let port=UInt16.random(in:49152...65000);let local=LocalWDA(port:port);driver=local
            local.onObservationCompleted={[weak self] in
                guard let self,!self.expired,self.requested else{return}
                self.work.observed();self.publishWork()
            }
            let config:[String:Any]=["runnerBundleId":Self.runner,"port":Int(port),"ddiDirectory":DeviceSecrets.ddiDirectory.path]
            let json=String(data:try JSONSerialization.data(withJSONObject:config),encoding:.utf8)!
            let result=bytes.withUnsafeBytes{buffer in json.withCString{ld_start(buffer.bindMemory(to:UInt8.self).baseAddress,bytes.count,$0)}}
            let value=Self.consume(result)
            if let code=value["error"] as? String{throw LineDrawError.message(Self.message(code))}
            let runnerDeadline=Date().addingTimeInterval(180)
            while Date()<runnerDeadline {
                try Task.checkCancellation();guard !expired else{throw CancellationError()}
                let status=Self.consume(ld_status());let stage=status["stage"] as? String ?? ""
                let code=status["code"] as? String ?? "";lastCode=code;onStage(Self.message(code))
                if stage=="failed" || stage=="stopped"{throw LineDrawError.message(Self.message(code))}
                if stage=="startingRunner",await local.ready(){
                    try await local.connect();lastCode="READY"
                    // Set the title before leaving our app. Repeated title changes while
                    // LINE is foreground expand Dynamic Island over its top-right Close.
                    background?.updateTitle("LineDraw 抽選",subtitle:"執行中；回到 LineDraw 可暫停或停止")
                    return local
                }
                try await Task.sleep(for:.milliseconds(500))
            }
            throw LineDrawError.message("啟動超過 180 秒，已停止。請檢查 VPN、DDI 與 Runner 簽章。")
        }catch{await stop(success:false);throw error}
    }
    func report(_ p:DeviceBatchProgress){
        work.update(p);publishWork()
    }
    private func publishWork(){
        // Successful observations are real completed work, including during a
        // slow page transition. A failed request or a timer never advances it.
        // Coalesce system-UI updates; changing its progress for every WDA reply
        // is unnecessary. This never sleeps or delays the next draw command.
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastWorkPublish>=4 else{return}
        lastWorkPublish=now
        let total=work.total,completed=work.completed
        if background?.progress.totalUnitCount != total{background?.progress.totalUnitCount=total}
        if background?.progress.completedUnitCount != completed{background?.progress.completedUnitCount=completed}
    }
    func stop(success:Bool,beforeCompletion:()->Void={})async{
        requested=false
        // Non-cancelled cleanup still closes WDA when the batch task was cancelled.
        if let local=driver{await Task{await local.shutdown()}.value};driver=nil;ld_stop()
        beforeCompletion()
        background?.setTaskCompleted(success:success);background=nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.taskID)
    }
    static func consume(_ ptr:UnsafeMutablePointer<CChar>?)->[String:Any]{guard let ptr else{return ["error":"BRIDGE_ERROR"]};defer{ld_string_free(ptr)};return (try? JSONSerialization.jsonObject(with:Data(String(cString:ptr).utf8))) as? [String:Any] ?? ["error":"BRIDGE_ERROR"]}
    static func message(_ code:String)->String{
        let messages=["DDI_CRYPTEX_MOUNT":"準備 iOS 27 開發者映像…","DDI_CRYPTEX_REQUIRED":"iOS 27 需要五個 Cryptex DDI 檔案，請完成首次匯入。","DDI_INVALID_MANIFEST":"DDI 描述檔不符合 Cryptex 格式。","DDI_CRYPTEX_MOUNT_FAILED":"iOS 27 開發者映像掛載失敗，已停止。","RP_CONNECT":"連接本機 Remote Pairing…","RP_CONNECT_TIMEOUT":"Remote Pairing 連線逾時，請確認 Wi-Fi 與 LocalDevVPN。","RP_CONNECT_FAILED":"無法連接本機 Remote Pairing 服務，請確認 VPN 與開發者模式。","RP_HANDSHAKE":"確認 Remote Pairing 服務…","RP_HANDSHAKE_FAILED":"Remote Pairing 服務未完成交握，已停止。","RP_VERIFY":"驗證這支手機的配對憑證…","RP_VERIFY_FAILED":"Remote Pairing 驗證失敗，請重新完成首次配對。","RP_TUNNEL":"建立本機開發者通道…","RP_LISTENER_FAILED":"手機無法建立開發者通道。","RP_TUNNEL_CONNECT":"無法連接開發者通道。","RP_TLS_TUNNEL_FAILED":"本機加密通道建立失敗，已停止。","RSD_HANDSHAKE":"探索手機開發者服務…","RSD_CONNECT_FAILED":"開發者服務通道中斷，已停止。","RSD_HANDSHAKE_FAILED":"無法取得開發者服務清單。","RSD_LOCKDOWN_FAILED":"無法驗證本機裝置資料。","VPN_SERVICE_PROBE":"確認本機開發者服務…","VPN_QUERY_TYPE_CLOSED":"本機開發者服務關閉了連線。請確認 Wi-Fi 與 LocalDevVPN；此 iOS 版本可能需要 Remote Pairing 啟動路徑。","VPN_SERVICE_CLOSED":"開發者服務未回應，請檢查本機 VPN 與 Wi-Fi。","VPN_SERVICE_TIMEOUT":"開發者服務查詢逾時，已停止。","VPN_CONNECT":"正在連接手機的開發者服務…","VPN_TIMEOUT":"無法連接本機 VPN，請開啟 LocalDevVPN。","VPN_CONNECT_FAILED":"請確認 LocalDevVPN 已連線。","PAIRING_INVALID":"配對檔格式不正確。","PAIRING_REJECTED":"配對檔已失效或不受信任，請重新配對。","PAIRING_TIMEOUT":"配對驗證逾時，請檢查 VPN。","DEVICE_MISMATCH":"這份配對檔屬於另一支手機。","DDI_CHECK":"檢查開發者磁碟映像…","DDI_MOUNT":"正在掛載開發者磁碟映像…","DDI_REQUIRED":"需先匯入對應系統的 DDI 檔案。","DDI_FILES_MISSING":"缺少 DDI 檔案，請匯入三個指定檔案。","DDI_MOUNT_FAILED":"DDI 掛載失敗，請檢查系統相容版本與網路。","DEVELOPER_MODE_DISABLED":"請先開啟 iPhone 開發者模式。","RUNNER_START":"正在啟動手機端 WDA…","RUNNER_NOT_INSTALLED":"尚未安裝 DeviceRunner，請完成首次簽署安裝。","XCTEST_SESSION_FAILED":"測試工作階段無法啟動，請確認 Runner 簽章、信任與 DDI。","HEARTBEAT_LOST":"開發者連線已中斷，已停止。","SESSION_EXISTS":"已有工作階段，請先停止後再試。","RUNNER_EXITED":"Runner 已結束。"]
        return messages[code] ?? "手機自主模式：\(code)"
    }
}

// Credentials are never stored in JSON, UserDefaults, documents, diagnostics, or exports.
@MainActor enum DeviceSecrets {
    static let service="com.beybladehunter.linedraw.device-pairing"
    static var query:[String:Any]{[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"local-device"]}
    static func load()throws->Data?{var q=query;q[kSecReturnData as String]=true;var result:CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&result);if status==errSecItemNotFound{return nil};guard status==errSecSuccess else{throw LineDrawError.message("無法讀取配對檔。請解鎖手機。")};return result as? Data}
    static func save(_ data:Data)throws{
        guard data.count<1_000_000,data.withUnsafeBytes({ld_validate_pairing($0.bindMemory(to:UInt8.self).baseAddress,data.count)}) == 1 else{throw LineDrawError.message("請匯入本機有效的配對檔；Remote Pairing 檔案需包含這支手機的識別資料。")}
        let attrs:[String:Any]=[kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status=SecItemUpdate(query as CFDictionary,attrs as CFDictionary)
        if status==errSecItemNotFound{var q=query;q.merge(attrs){_,new in new};guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else{throw LineDrawError.message("無法儲存配對檔。")}}
        else if status != errSecSuccess{throw LineDrawError.message("無法更新配對檔。")}
    }
    static func clear(){SecItemDelete(query as CFDictionary)}
    static var ddiDirectory:URL{FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LineDraw-DDI",isDirectory:true)}
    static let filenames=DDIPackage.filenames
    static var ddiReady:Bool{DDIManager.cachedBuild != nil}
    static func importDDI(_ urls:[URL])throws{
        guard Set(urls.map(\.lastPathComponent))==Set(filenames),urls.count==filenames.count else{throw LineDrawError.message("請一次選取首次設定工具準備的五個 DDI 檔案。")}
        let fm=FileManager.default,staging=fm.temporaryDirectory.appendingPathComponent("DDI-import-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:true);defer{try? fm.removeItem(at:staging)}
        for url in urls {
            let granted=url.startAccessingSecurityScopedResource();defer{if granted{url.stopAccessingSecurityScopedResource()}}
            let meta=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard meta.isRegularFile==true,meta.isSymbolicLink != true,let size=meta.fileSize,size>0,size<=100_000_000 else{throw LineDrawError.message("DDI 檔案格式或大小不正確。")}
            try fm.copyItem(at:url,to:staging.appendingPathComponent(url.lastPathComponent))
        }
        try DDIPackage.install(staging,to:ddiDirectory)
    }
}
