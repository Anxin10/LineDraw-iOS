import Foundation
import CryptoKit
import UIKit
import LineDrawCore

@MainActor enum DDIManager {
    static var cachedBuild:String?{(try? DDIPackage.validate(DeviceSecrets.ddiDirectory))?.build}
    static func prepare(target:URL?=nil,allowBundled:Bool=true,onStage:@escaping(String)->Void)async throws {
        let destination=target ?? DeviceSecrets.ddiDirectory
        onStage("檢查必要檔案…")
        let valid=await Task.detached{(try? DDIPackage.validate(destination)) != nil}.value
        try Task.checkCancellation();if valid{onStage("DDI 已就緒，使用本機快取。");return}
        if allowBundled,let bundled=Bundle.main.url(forResource:"BundledDDI",withExtension:nil),
           (try? DDIPackage.validate(bundled)) != nil {
            onStage("自動準備隨附的 DDI…")
            try await Task.detached{try DDIPackage.install(bundled,to:destination)}.value
            try Task.checkCancellation();onStage("DDI 已自動準備完成。");return
        }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion==27 else{throw LineDrawError.message("此系統尚無已驗證的自動 DDI 版本，請更新 App 或手動匯入。")}
        // Fixed upstream revision and hashes. No executable/pairing data is downloaded.
        let fm=FileManager.default,staging=fm.temporaryDirectory.appendingPathComponent("DDI-download-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:true);defer{try? fm.removeItem(at:staging)}
        let transport=DDIDownloadGuard();let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=30;configuration.timeoutIntervalForResource=240
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session=URLSession(configuration:configuration,delegate:transport,delegateQueue:nil);defer{session.invalidateAndCancel()}
        for (i,file) in DDIDownloadCatalog.files.enumerated(){
            try Task.checkCancellation();onStage("下載 DDI \(i+1) / \(DDIDownloadCatalog.files.count)：\(file.name)…")
            let url=DDIDownloadCatalog.base.appendingPathComponent(file.name)
            let (temp,response)=try await session.download(from:url)
            defer{try? fm.removeItem(at:temp)}
            guard let http=response as? HTTPURLResponse,http.statusCode==200,http.url==url else{throw LineDrawError.message("DDI 下載失敗；請恢復網路後再試。原有檔案已保留。")}
            let bytes=try Data(contentsOf:temp,options:.mappedIfSafe)
            guard bytes.count==file.size,SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==file.sha256 else{throw LineDrawError.message("DDI 下載內容未通過完整性驗證，已取消安裝。")}
            try fm.moveItem(at:temp,to:staging.appendingPathComponent(file.name))

        }
        try Task.checkCancellation();onStage("驗證並儲存 DDI…")
        try await Task.detached{try DDIPackage.install(staging,to:destination)}.value
        try Task.checkCancellation();onStage("DDI 已下載並快取完成。")
    }
}

private final class DDIDownloadGuard:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){
        let limit=DDIDownloadCatalog.files.first{$0.name==downloadTask.originalRequest?.url?.lastPathComponent}?.size ?? 0
        if totalBytesWritten>limit || totalBytesExpectedToWrite>limit{downloadTask.cancel()}
    }
}
