import Foundation

public enum CatalogSource:String,Codable,CaseIterable,Identifiable,Sendable{
    case funbox
    case beybladeHunter="beybladehunter"
    public var id:String{rawValue}
    public var title:String{self == .funbox ? "Funbox 原站":"陀螺獵人"}
    public var pageURL:URL{self == .funbox ? CatalogParser.sourceURL:URL(string:"https://beybladehunter.com/funbox.html")!}
    public var dataURL:URL{self == .funbox ? pageURL:URL(string:"https://beybladehunter.com/api/funbox/data")!}
    public static let hunterPrefix="catalog:beybladehunter:"
    public func owns(_ draw:Draw)->Bool{draw.area == .website && (self == .beybladeHunter ? draw.id.hasPrefix(Self.hunterPrefix):!draw.id.hasPrefix("catalog:"))}
    public func parse(_ payload:String)throws->[Draw]{
        if self == .funbox{return try CatalogParser.parse(payload)}
        return try BeybladeHunterParser.parse(payload)
    }
}
public struct CatalogSync:Codable,Sendable{
    public var lastSync:Date?
    public var summary:String
    public init(lastSync:Date?,summary:String){self.lastSync=lastSync;self.summary=summary}
}
public enum BeybladeHunterParser{
    private struct Payload:Decodable{let draws:[Row]}
    private struct Row:Decodable{
        let id:String;let line_url:String;let city:String;let store_name:String;let product_name:String;let start_time:String?;let end_time:String?
        enum CodingKeys:String,CodingKey{case id,line_url,city,store_name,product_name,start_time,end_time}
        init(from decoder:Decoder)throws{
            let c=try decoder.container(keyedBy:CodingKeys.self)
            if let number=try? c.decode(Int64.self,forKey:.id){id=String(number)}else{id=try c.decode(String.self,forKey:.id)}
            line_url=try c.decode(String.self,forKey:.line_url);city=try c.decode(String.self,forKey:.city);store_name=try c.decode(String.self,forKey:.store_name);product_name=try c.decode(String.self,forKey:.product_name)
            start_time=try c.decodeIfPresent(String.self,forKey:.start_time);end_time=try c.decodeIfPresent(String.self,forKey:.end_time)
        }
    }
    public static func parse(_ payload:String)throws->[Draw]{
        guard payload.utf8.count<=2_000_000 else{throw LineDrawError.message("來源資料過大，保留前次清單。")}
        let input:Payload
        do{input=try JSONDecoder().decode(Payload.self,from:Data(payload.utf8))}catch{throw LineDrawError.message("陀螺獵人資料格式異常，保留前次清單。")}
        guard input.draws.count<=5000 else{throw LineDrawError.message("抽選筆數異常。")}
        let format=DateFormatter();format.locale=Locale(identifier:"en_US_POSIX");format.calendar=Calendar(identifier:.gregorian);format.timeZone=TimeZone(identifier:"Asia/Taipei")!;format.dateFormat="yyyy-MM-dd HH:mm:ss";format.isLenient=false
        let display=DateFormatter();display.locale=Locale(identifier:"zh_TW");display.timeZone=format.timeZone;display.dateFormat="yyyy/MM/dd HH:mm"
        func time(_ raw:String?)throws->Date?{
            guard let raw,!raw.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
            guard let value=format.date(from:raw),format.string(from:value)==raw else{throw LineDrawError.message("抽選時間格式異常，保留前次清單。")};return value
        }
        func text(_ raw:String,limit:Int)throws->String{
            let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !value.isEmpty,value.count<=limit else{throw LineDrawError.message("活動資料不完整，保留前次清單。")};return value
        }
        var ids=Set<String>()
        return try input.draws.enumerated().map{index,row in
            guard row.id.range(of:"^[1-9][0-9]{0,18}$",options:.regularExpression) != nil,Int64(row.id) != nil,ids.insert(row.id).inserted else{throw LineDrawError.message("來源 ID 無效或重複，保留前次清單。")}
            let store=try text(row.store_name,limit:255),city=try text(row.city,limit:50),product=try text(row.product_name,limit:500),url=try text(row.line_url,limit:2000)
            guard LinkPolicy.allowed(url) else{throw LineDrawError.message("抽選連結異常，保留前次清單。")}
            // API 的 MySQL DATETIME 固定以台北時間解讀，不依手機時區猜測。
            let start=try time(row.start_time),end=try time(row.end_time)
            guard start==nil || end==nil || end!>=start! else{throw LineDrawError.message("抽選結束時間早於開始時間。")}
            let label="抽選時間：\(start.map{display.string(from:$0)} ?? "開始時間未提供")~\(end.map{display.string(from:$0)} ?? "結束時間未提供")"
            return Draw(id:CatalogSource.hunterPrefix+row.id+":"+String(LinkPolicy.digest(url).prefix(16)),activityKey:LinkPolicy.key(url,store:store,period:label),store:store,city:city,product:product,url:url,canonicalURL:LinkPolicy.canonical(url),timeLabel:label,startsAt:start,endsAt:end,ordinal:index)
        }
    }
}

public extension DatabaseSnapshot {
    /// Legacy snapshots have only Funbox sync metadata. Never use it for another source.
    func syncStatus(for source:CatalogSource)->CatalogSync {
        if let status=catalogSync?[source.rawValue] {return status}
        return source == .funbox
            ? CatalogSync(lastSync:lastSync,summary:syncSummary)
            : CatalogSync(lastSync:nil,summary:"尚未同步")
    }
}
