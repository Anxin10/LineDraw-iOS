import Foundation
import CryptoKit

public enum DrawArea: String, Codable, CaseIterable, Sendable { case website, test, demo
    public var title: String { switch self { case .website: "網站抽選"; case .test: "五連結測試"; case .demo: "離線示範" } }
}
public enum Eligibility: String, Codable, Sendable { case ready, notStarted, expired, unknown, archived
    public var title: String { switch self { case .ready: "可抽選"; case .notStarted: "尚未開始"; case .expired: "已截止"; case .unknown: "時間未確認"; case .archived: "已封存" } }
}
public struct Draw: Codable, Identifiable, Hashable, Sendable {
    public var syncIssue:String? = nil
    public var id: String; public var activityKey: String; public var store: String; public var city: String
    public var product: String; public var url: String; public var canonicalURL: String?; public var timeLabel: String
    public var startsAt: Date?; public var endsAt: Date?; public var ordinal: Int; public var archived: Bool; public var area: DrawArea
    public init(id: String, activityKey: String, store: String, city: String, product: String, url: String, canonicalURL: String? = nil, timeLabel: String = "", startsAt: Date?, endsAt: Date?, ordinal: Int, archived: Bool = false, area: DrawArea = .website) {
        self.id=id; self.activityKey=activityKey; self.store=store; self.city=city; self.product=product; self.url=url; self.canonicalURL=canonicalURL; self.timeLabel=timeLabel; self.startsAt=startsAt; self.endsAt=endsAt; self.ordinal=ordinal; self.archived=archived; self.area=area
    }
    public func eligibility(at now: Date = Date()) -> Eligibility {
        if archived { return .archived }; if let start=startsAt, now < start { return .notStarted }; if let end=endsAt, now >= end { return .expired }
        return startsAt == nil || endsAt == nil ? .unknown : .ready
    }
    public func runnable(at now: Date = Date()) -> Bool { syncIssue == nil && eligibility(at: now) == .ready && canonicalURL != nil }
}
public enum DrawStatusFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case ready, notStarted, unknown, recorded, expired, archived
    public var id: String { rawValue }
    public var title: String { switch self { case .ready: "可抽選"; case .notStarted: "尚未開始"; case .unknown: "時間未確認"; case .recorded: "已有紀錄"; case .expired: "已截止"; case .archived: "已封存" } }
}
public struct CatalogFilter: Codable, Equatable, Sendable {
    public var cities: Set<String> = []; public var statuses: Set<DrawStatusFilter> = []; public var query = ""
    public init() {}
    public func matches(_ draw: Draw, recorded: Bool, now: Date = Date()) -> Bool {
        guard cities.isEmpty || cities.contains(draw.city) else { return false }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !"\(draw.store) \(draw.product) \(draw.city)".localizedCaseInsensitiveContains(query) { return false }
        if statuses.isEmpty { return !draw.archived }
        return statuses.contains { status in
            if status == .archived { return draw.archived }; if draw.archived { return false }
            switch status { case .ready: return draw.runnable(at: now) && !recorded; case .notStarted: return draw.eligibility(at: now) == .notStarted; case .unknown: return draw.eligibility(at: now) == .unknown; case .recorded: return recorded; case .expired: return draw.eligibility(at: now) == .expired; case .archived: return false }
        }
    }
}
public struct ParticipationRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String; public var product: String; public var store: String; public var status: String; public var evidence: String; public var updatedAt: Date
    public init(id: String, product: String, store: String, status: String, evidence: String, updatedAt: Date = Date()) { self.id=id;self.product=product;self.store=store;self.status=status;self.evidence=evidence;self.updatedAt=updatedAt }
    public var blocksRepeat: Bool { ["SUBMITTED","COMPLETE","ALREADY","MANUAL","REVIEW","ENDED"].contains(status) || status.hasSuffix("_INTENT") }
    public var title: String { ["SUBMITTED":"已送出","COMPLETE":"已完成","ALREADY":"已抽過／已領取","MANUAL":"已完成（手動）","REVIEW":"待確認","ENDED":"活動已結束","LOAD_TIMEOUT":"載入逾時","SKIPPED":"已略過","FRIEND_ADDED":"已加入好友"][status] ?? (status.hasSuffix("_INTENT") ? "操作中" : status) }
    public var canMarkManually: Bool { ["SUBMITTED","REVIEW","LOAD_TIMEOUT","ENDED","SKIPPED"].contains(status) }
}
public struct AppSettings: Codable, Sendable {
    public var scanLookupMode:String?
    public var batchLookupMode:String?
    public var profile = "預設"; public var profiles = ["預設"]; public var autoFriend = true; public var autoContinue = true
    public var appearance = "system"; public var reduceTransparency = false; public var reduceMotion = false
    public init() {}
}
public struct Diagnostic: Codable, Identifiable, Sendable {
    public var id = UUID(); public var at = Date(); public var code: String; public var message: String
    public init(at:Date=Date(),code:String,message:String){self.at=at;self.code=code;self.message=message}
}
public struct ManualUndo: Codable, Sendable { public var previous: ParticipationRecord? }
public struct DatabaseSnapshot: Codable, Sendable {
    public var version=1; public var draws: [Draw]=[]; public var records: [String:ParticipationRecord]=[:]; public var manualUndo: [String:ManualUndo]=[:]
    public var selectedCatalog:CatalogSource?; public var catalogSync:[String:CatalogSync]?
    public var settings=AppSettings(); public var consentVersion=0; public var lastSync: Date?; public var syncSummary="尚未同步"; public var diagnostics: [Diagnostic]=[]
    public var bridgeOutbox: [RecordMutation]=[]
    public init() {}
}
public struct RecordMutation: Codable, Identifiable, Sendable {
    public var id=UUID(); public var profile: String; public var area: DrawArea; public var activityKey: String; public var action: String
    public var product: String; public var store: String
}
public enum LineDrawError: LocalizedError, Equatable { case message(String)
    public var errorDescription: String? { if case .message(let message)=self { return message };return nil }
}
public enum LinkPolicy {
    public static func digest(_ text: String) -> String { SHA256.hash(data:Data(text.utf8)).map { String(format:"%02x",$0) }.joined() }
    public static func allowed(_ raw: String) -> Bool {
        guard let c=URLComponents(string:raw),c.scheme=="https",["lin.ee","liff.line.me","line.me"].contains(c.host ?? ""),c.user==nil,c.password==nil,c.port==nil || c.port==443,!c.path.isEmpty,c.path != "/" else { return false };return true
    }
    public static func canonical(_ raw: String) -> String? {
        guard allowed(raw),let c=URLComponents(string:raw),c.host=="liff.line.me",c.query==nil,c.fragment==nil,
              c.path.range(of:"^/[A-Za-z0-9_-]+/c/[A-Za-z0-9_-]+$",options:.regularExpression) != nil else { return nil }
        return "https://liff.line.me"+c.path
    }
    public static func key(_ raw: String, store: String="", period: String="") -> String {
        if let canonical=canonical(raw),let url=URL(string:canonical) { let parts=url.path.split(separator:"/");return "coupon:\(parts[0]):\(parts[2])" }
        return "url:"+digest(store+"\n"+raw+"\n"+period)
    }
}
public enum UsageDeclaration {
    public static let version=2
    public static let paragraphs=["LineDraw 是公開原始碼、限非商業使用的 LINE 抽選輔助工具，無需登入或 VIP 資格。","開始批次後，手機自主模式或已配對的 Mac 會控制這支 iPhone，依序開啟活動；經你啟用後，也會加入店家好友並送出抽選。","已送出代表點擊指令完成，不代表中獎。遇到登入、驗證碼或不確定的操作狀態時會暫停。","手機自主模式需完成開發者簽署、配對、DDI 與本機 VPN 設定，尚屬實驗功能。活動與紀錄保存在你的裝置；使用 Mac 模式時也會同步至配對的 Mac。你可隨時停止批次、解除配對；不同意則不啟用本工具。"]
}
