import Foundation

public struct LocalDatabase {
    public private(set) var snapshot: DatabaseSnapshot
    public let file: URL
    public init(file:URL) throws {
        self.file=file
        if FileManager.default.fileExists(atPath:file.path){snapshot=try WireJSON.decoder().decode(DatabaseSnapshot.self,from:Data(contentsOf:file));guard snapshot.version==1 else{throw LineDrawError.message("資料版本不支援，原檔已保留。")}}
        else{snapshot=DatabaseSnapshot()}
    }
    public static func scope(profile:String,area:DrawArea)->String { "\(profile.utf8.count):\(profile):\(area.rawValue)" }
    public func records(profile:String,area:DrawArea)->[String:ParticipationRecord] {
        let prefix=Self.scope(profile:profile,area:area)+"\n"
        return Dictionary(uniqueKeysWithValues:snapshot.records.filter{$0.key.hasPrefix(prefix)}.map{(String($0.key.dropFirst(prefix.count)),$0.value)})
    }
    public mutating func update(_ operation:(inout DatabaseSnapshot)throws->Void)throws{
        var candidate=snapshot;try operation(&candidate)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try WireJSON.encoder().encode(candidate).write(to:file,options:.atomic);snapshot=candidate
    }
    public mutating func merge(_ incoming:[Draw],area:DrawArea,now:Date=Date())throws{
        guard !incoming.isEmpty, incoming.allSatisfy({$0.area==area}),Set(incoming.map(\.id)).count==incoming.count else{throw LineDrawError.message("同步清單不完整，保留前次資料。")}
        var incoming=incoming
        for i in incoming.indices where incoming[i].canonicalURL==nil{if let previous=snapshot.draws.first(where:{$0.area==area && $0.id==incoming[i].id && $0.url==incoming[i].url}),let canonical=previous.canonicalURL{incoming[i].canonicalURL=canonical;incoming[i].activityKey=previous.activityKey}}
        let current=snapshot.draws.filter{$0.area==area && !$0.archived};let ids=Set(incoming.map(\.id));let old=Dictionary(uniqueKeysWithValues:current.map{($0.id,$0)})
        let added=incoming.filter{old[$0.id]==nil}.count;let removed=current.filter{!ids.contains($0.id)}.count
        try update{ db in
            var archived=db.draws.filter{$0.area==area && !ids.contains($0.id)};for i in archived.indices{archived[i].archived=true}
            db.draws=db.draws.filter{$0.area != area}+incoming+archived
            if area == .website {db.lastSync=now;db.syncSummary="\(incoming.count) 筆 · 新增 \(added) · 封存 \(removed)"}
        }
    }
    public mutating func refreshBuiltInTests()throws{
        let current=snapshot.draws.filter{$0.area == .test && !$0.archived}
        guard current.isEmpty || TestCatalog.previousBuiltInCatalogs.contains(Set(current.map(\.id))) else{return}
        try merge(TestCatalog.five(),area:.test)
    }
    public mutating func manual(_ draw:Draw,profile:String)throws{
        let key=Self.scope(profile:profile,area:draw.area)+"\n"+draw.activityKey
        let previous=snapshot.records[key]
        guard previous==nil || previous!.canMarkManually else{throw LineDrawError.message("這筆已有完成紀錄。")}
        try update{ db in
            db.manualUndo[key]=ManualUndo(previous:previous)
            db.records[key]=ParticipationRecord(id:draw.activityKey,product:draw.product,store:draw.store,status:"MANUAL",evidence:"使用者手動標記；不代表中獎。")
            if draw.area != .demo{db.bridgeOutbox.append(RecordMutation(profile:profile,area:draw.area,activityKey:draw.activityKey,action:"manual",product:draw.product,store:draw.store))}
        }
    }
    public mutating func undo(activityKey:String,profile:String,area:DrawArea)throws{
        let key=Self.scope(profile:profile,area:area)+"\n"+activityKey
        guard snapshot.records[key]?.status=="MANUAL",let backup=snapshot.manualUndo[key] else{throw LineDrawError.message("缺少原始紀錄，保留手動完成狀態。")}
        let old=snapshot.records[key]!
        try update{db in
            db.records[key]=backup.previous;db.manualUndo.removeValue(forKey:key)
            if area != .demo{db.bridgeOutbox.append(RecordMutation(profile:profile,area:area,activityKey:activityKey,action:"undo",product:old.product,store:old.store))}
        }
    }
    public mutating func importRecords(_ records:[ParticipationRecord],profile:String,area:DrawArea)throws{
        let prefix=Self.scope(profile:profile,area:area)+"\n"
        let pending=Set(snapshot.bridgeOutbox.filter{$0.profile==profile && $0.area==area}.map(\.activityKey))
        try update{db in
            for record in records where !pending.contains(record.id) {
                // Preserve local manual-undo metadata and never let an older poll undo a newer state.
                if let old=db.records[prefix+record.id],old.updatedAt>record.updatedAt{continue}
                db.records[prefix+record.id]=record
            }
        }
    }
    public mutating func log(_ code:String,_ message:String,now:Date=Date())throws{
        try update{db in db.diagnostics=db.diagnostics.filter{$0.at>now.addingTimeInterval(-30*86400)};db.diagnostics.append(Diagnostic(at:now,code:code,message:message));db.diagnostics=Array(db.diagnostics.suffix(300))}
    }
    public func diagnosticsText()->String{
        "LineDraw iOS 1.0 · 本機診斷\n"+snapshot.diagnostics.map{"\(WireJSON.date($0.at)) \($0.code) \($0.message)"}.joined(separator:"\n")
    }
}
public enum WireJSON {
    public static func date(_ date:Date)->String {let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.string(from:date)}
    public static func parseDate(_ string:String)->Date? {let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:string) ?? ISO8601DateFormatter().date(from:string)}
    public static func encoder()->JSONEncoder {let e=JSONEncoder();e.outputFormatting=[.sortedKeys];e.dateEncodingStrategy = .custom{date,encoder in var c=encoder.singleValueContainer();try c.encode(Self.date(date))};return e}
    public static func decoder()->JSONDecoder {let d=JSONDecoder();d.dateDecodingStrategy = .custom{decoder in let c=try decoder.singleValueContainer();let value=try c.decode(String.self);guard let date=Self.parseDate(value) else{throw DecodingError.dataCorruptedError(in:c,debugDescription:"Invalid timestamp")};return date};return d}
}
