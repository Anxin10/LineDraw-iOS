import Foundation

public enum ObservationFailure:Error,LocalizedError,Equatable,Sendable {
    case deadlineExceeded, exhausted, staleObservation, concurrentRequest, invalidXML
    public var errorDescription:String? {
        switch self {
        case .deadlineExceeded:return "本筆操作時間已用完。"
        case .exhausted:return "本筆畫面查詢次數已用完。"
        case .staleObservation:return "畫面已失效，未執行操作。"
        case .concurrentRequest:return "手機查詢尚未結束，已停止避免重疊操作。"
        case .invalidXML:return "畫面 XML 不完整或超過限制。"
        }
    }
}
/// Uses monotonic system uptime, shared with the queue's injectable clock.
public struct QueryContext:Sendable,Equatable {
    public let itemID:UUID
    public let navigationID:UUID
    public let deadline:TimeInterval
    public init(itemID:UUID=UUID(),navigationID:UUID=UUID(),deadline:TimeInterval){
        self.itemID=itemID;self.navigationID=navigationID;self.deadline=deadline
    }
    public func timeout(cap:TimeInterval,now:TimeInterval=ProcessInfo.processInfo.systemUptime,minimum:TimeInterval=0)throws->TimeInterval {
        let remaining=deadline-now
        guard remaining>0,remaining>=minimum else{throw ObservationFailure.deadlineExceeded}
        return min(cap,remaining)
    }
    public func navigating()->Self{.init(itemID:itemID,deadline:deadline)}
}
public struct ObservationPolicy:Sendable {
    public enum Kind:Sendable {case targeted,xml,ocr}
    public private(set) var targeted=0,xml=0,ocr=0
    public private(set) var incomplete=0
    public init(){}
    public mutating func recordIncomplete(){incomplete+=1}
    public mutating func recordComplete(){incomplete=0}
    public mutating func consume(_ kind:Kind)throws {
        switch kind {
        case .targeted:guard targeted<6 else{throw ObservationFailure.exhausted};targeted+=1
        case .xml:guard xml<2 else{throw ObservationFailure.exhausted};xml+=1
        case .ocr:guard ocr<2 else{throw ObservationFailure.exhausted};ocr+=1
        }
    }
    public var canTarget:Bool{targeted<6}
    public var shouldUseXML:Bool{incomplete>=2 || !canTarget}
}
