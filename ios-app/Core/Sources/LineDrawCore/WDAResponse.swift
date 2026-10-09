import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WDAResponseFailure:LocalizedError,Sendable {
    public let operation:String
    public let status:Int
    public let code:String
    public let remoteMessage:String
    public init(operation:String,status:Int,code:String,remoteMessage:String){self.operation=operation;self.status=status;self.code=code;self.remoteMessage=remoteMessage}
    public var canRetryRead:Bool {
        if ["invalid session id","invalid argument","unsupported operation"].contains(code){return false}
        return [200,404,500,502,503,504].contains(status) && ["unknown error","timeout","stale element reference","no such element","no such window","invalid JSON","missing value","unexpected value","HTTP error"].contains(code)
    }
    public var errorDescription:String?{
        if operation=="POST url",code=="unknown error",remoteMessage.lowercased().contains("device is locked") {
            return "iPhone 已鎖定，無法開啟活動；請解鎖後重新開始。"
        }
        return "手機端 WDA 指令失敗（\(operation)，HTTP \(status)，\(code)）。"
    }
}
public enum WDAResponse {
    public static func decode(_ data:Data,response:URLResponse,operation:String)throws->Any {
        let status=(response as? HTTPURLResponse)?.statusCode ?? 0
        func failure(_ code:String,_ message:String="")->WDAResponseFailure{.init(operation:operation,status:status,code:code,remoteMessage:message)}
        guard data.count<12_000_000 else{throw failure("response too large")}
        guard let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{throw failure("invalid JSON")}
        if let error=json["value"] as? [String:Any],let raw=error["error"] as? String {
            let codes:Set<String>=["unknown error","invalid session id","stale element reference","no such element","timeout","invalid argument","unsupported operation","no such window"]
            throw failure(codes.contains(raw) ? raw:"remote error",error["message"] as? String ?? "")
        }
        guard (200..<300).contains(status) else{throw failure("HTTP error")}
        guard let value=json["value"] else{throw failure("missing value")}
        if operation=="GET source",!(value is String) || (value as? String)?.isEmpty==true{throw failure("unexpected value")}
        if operation=="GET source.json",!(value is [String:Any]){throw failure("unexpected value")}
        if operation=="GET wda/activeAppInfo",((value as? [String:Any])?["bundleId"] as? String)?.isEmpty != false{throw failure("unexpected value")}
        return value // WDA acknowledges successful actions with JSON null.
    }
}
