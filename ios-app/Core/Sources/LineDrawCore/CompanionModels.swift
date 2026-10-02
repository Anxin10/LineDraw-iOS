import Foundation
public struct PairingInvitation: Codable, Sendable {
    public var endpoint:String;public var fingerprint:String;public var code:String
    public init(raw:String)throws{
        guard let url=URLComponents(string:raw.trimmingCharacters(in:.whitespacesAndNewlines)),url.scheme=="linedraw",url.host=="pair",url.fragment==nil,let items=url.queryItems,items.count==3,Set(items.map(\.name))==Set(["endpoint","fingerprint","code"]) else{throw LineDrawError.message("配對碼格式不正確，請重新掃描 Mac 控制台。")}
        let values=Dictionary(uniqueKeysWithValues:items.map{($0.name,$0.value ?? "")})
        endpoint=values["endpoint"]!;fingerprint=values["fingerprint"]!.lowercased();code=values["code"]!
        guard Self.localEndpoint(endpoint),fingerprint.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,code.range(of:"^[0-9]{6}$",options:.regularExpression) != nil else{throw LineDrawError.message("配對碼不是有效的區域網路連線。")}
    }
    public static func localEndpoint(_ raw:String)->Bool{
        guard let c=URLComponents(string:raw),c.scheme=="https",let host=c.host,c.user==nil,c.password==nil,c.query==nil,c.fragment==nil,c.path.isEmpty || c.path=="/",let port=c.port,(1024...65535).contains(port) else{return false}
        if host.hasSuffix(".local") && host.count<254{return true}
        let p=host.split(separator:".").compactMap{Int($0)};guard p.count==4,p.allSatisfy({(0...255).contains($0)}) else{return false}
        return p[0]==10 || p[0]==192 && p[1]==168 || p[0]==172 && (16...31).contains(p[1]) || p[0]==127
    }
}
public struct PairingCredential: Codable, Sendable {public var endpoint:String;public var fingerprint:String;public var token:String;public var name:String
    public init(endpoint:String,fingerprint:String,token:String,name:String){self.endpoint=endpoint;self.fingerprint=fingerprint;self.token=token;self.name=name}
}
public struct CompanionRecord: Codable, Sendable {public var id:String;public var product:String;public var store:String;public var status:String;public var reason:String;public var at:Date
    public var local:ParticipationRecord{ParticipationRecord(id:id,product:product,store:store,status:status,evidence:reason,updatedAt:at)}
}
public struct CompanionQueueItem:Codable,Identifiable,Sendable{public var id:String;public var title:String;public var record:CompanionQueueRecord?}
public struct CompanionQueueRecord:Codable,Sendable{public var status:String;public var reason:String;public var at:Date}
public struct CompanionEngine:Codable,Sendable{
    public var state:String;public var reason:String;public var index:Int;public var total:Int;public var busy:Bool;public var current:String?;public var queue:[CompanionQueueItem]
    public var locked:Bool{busy || state=="RUNNING" || state=="PAUSED"}
}
public struct CompanionStatus:Codable,Sendable{
    public var catalogSources:[String]?;public var connected:Bool;public var engine:CompanionEngine;public var records:[CompanionRecord];public var profile:String;public var area:String;public var round:Int;public var diagnostics:[CompanionEvent]
}
public struct CompanionEvent:Codable,Sendable{public var at:Date;public var code:String;public var index:Int?;public var detail:String}
public struct CompanionStart:Codable,Sendable{
    public var catalogSource:CatalogSource?;public var requestID:String;public var profile:String;public var area:DrawArea;public var rows:[Draw];public var selectedIDs:[String];public var records:[ParticipationRecord];public var filter:CatalogFilter;public var autoFriend:Bool;public var autoContinue:Bool;public var accepted:Bool
    public init(profile:String,area:DrawArea,rows:[Draw],selectedIDs:[String],records:[ParticipationRecord],filter:CatalogFilter,autoFriend:Bool,autoContinue:Bool,catalogSource:CatalogSource = .funbox){self.catalogSource=catalogSource;requestID=UUID().uuidString;self.profile=profile;self.area=area;self.rows=rows;self.selectedIDs=selectedIDs;self.records=records;self.filter=filter;self.autoFriend=autoFriend;self.autoContinue=autoContinue;accepted=true}
}
