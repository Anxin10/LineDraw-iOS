import Foundation
import SwiftSoup

public enum DrawSchedule {
    public static func parse(_ raw: String) throws -> (Date?,Date?) {
        let normalized=raw.replacingOccurrences(of:"：",with:":").replacingOccurrences(of:"／",with:"/").replacingOccurrences(of:"[（(](?:星期|週|周)?[一二三四五六日天][）)]",with:" ",options:.regularExpression)
        guard let clause=normalized.components(separatedBy:CharacterSet(charactersIn:"｜|；;\n")).first(where:{$0.range(of:"抽[選籤]",options:.regularExpression) != nil}),let startRange=clause.range(of:"抽[選籤]",options:.regularExpression) else { return (nil,nil) }
        let text=String(clause[startRange.lowerBound...]);let pattern="\\d{4}/\\d{1,2}/\\d{1,2}\\s+\\d{1,2}:\\d{2}"
        guard let first=text.range(of:pattern,options:.regularExpression) else { return (nil,nil) }
        let start=date(String(text[first]));let tail=String(text[first.upperBound...])
        let endMatch=tail.range(of:"^\\s*[~～至到－—–-]\\s*("+pattern+")",options:.regularExpression)
        let end=endMatch.flatMap { range -> Date? in let content=String(tail[range]);guard let r=content.range(of:pattern,options:.regularExpression) else { return nil };return date(String(content[r])) }
        if let start,let end,end<=start { throw LineDrawError.message("抽選起訖時間衝突，保留前次清單。") };return (start,end)
    }
    private static func date(_ raw: String) -> Date? {
        let values=raw.split(whereSeparator:{!$0.isNumber}).compactMap{Int($0)};guard values.count==5 else{return nil}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Asia/Taipei")!
        let components=DateComponents(year:values[0],month:values[1],day:values[2],hour:values[3],minute:values[4])
        guard let date=calendar.date(from:components) else{return nil};let actual=calendar.dateComponents([.year,.month,.day,.hour,.minute],from:date)
        return actual==components ? date:nil
    }
}
public enum CatalogParser {
    public static let sourceURL=URL(string:"https://uxux11.github.io/funbox-line/")!
    public static func parse(_ html: String) throws -> [Draw] {
        guard html.utf8.count<=2_000_000 else{throw LineDrawError.message("來源頁面過大，保留前次清單。")}
        let doc=try SwiftSoup.parse(html);let stores=try doc.select("#page-draws .draw-store")
        guard !stores.isEmpty() else{throw LineDrawError.message("找不到抽選區，保留前次清單。")}
        var result:[Draw]=[];var seen=Set<String>()
        for store in stores.array() {
            let name=try store.select(".draw-store-name").first()?.text().trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
            let city=try store.attr("data-draw-city");let label=try store.select(".draw-start").first()?.text() ?? ""
            let (start,end)=try DrawSchedule.parse(label);let rows=try store.select(".draw-item[data-draw-id][data-draw-href]")
            guard !name.isEmpty,name.count<200,!rows.isEmpty(),rows.size()==(try store.select(".draw-item").size()) else{throw LineDrawError.message("店家抽選資料不完整，保留前次清單。")}
            for row in rows.array() {
                let sourceID=try row.attr("data-draw-id").trimmingCharacters(in:.whitespacesAndNewlines)
                let url=try row.attr("data-draw-href").trimmingCharacters(in:.whitespacesAndNewlines)
                let product=try row.select(".draw-product").first()?.text() ?? ""
                guard !sourceID.isEmpty,seen.insert(sourceID).inserted,!product.isEmpty,product.count<500,LinkPolicy.allowed(url) else{throw LineDrawError.message("抽選列缺漏、重複或連結異常，保留前次清單。")}
                result.append(Draw(id:sourceID+":"+String(LinkPolicy.digest(url).prefix(16)),activityKey:LinkPolicy.key(url,store:name,period:label),store:name,city:city.isEmpty ? "未分類":city,product:product,url:url,canonicalURL:LinkPolicy.canonical(url),timeLabel:label,startsAt:start,endsAt:end,ordinal:result.count))
            }
        }
        guard (1...5000).contains(result.count) else{throw LineDrawError.message("抽選筆數異常。")};return result
    }
}
/// Refuse redirects before dispatch so a source link cannot send requests to unrelated hosts.
public final class CatalogNetwork: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public override init(){super.init()}
    public func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
    private func get(_ url:URL,limit:Int) async throws -> (Data,HTTPURLResponse) {
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=20;config.httpCookieStorage=nil;config.urlCache=nil
        let session=URLSession(configuration:config,delegate:self,delegateQueue:nil);defer{session.invalidateAndCancel()}
        var request=URLRequest(url:url);request.setValue("LineDraw-OpenSource/1.0",forHTTPHeaderField:"User-Agent")
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse else{throw LineDrawError.message("來源回應異常。")}
        var data=Data();for try await byte in bytes { if data.count>=limit{throw LineDrawError.message("來源回應過大。")};data.append(byte) };return(data,http)
    }
    public func resolve(_ raw:String) async throws -> String {
        if let canonical=LinkPolicy.canonical(raw){return canonical}
        var current=raw;var seen=Set<String>()
        for _ in 0..<5 {
            guard LinkPolicy.allowed(current),seen.insert(current).inserted,let url=URL(string:current) else{throw LineDrawError.message("抽選連結導向異常。")}
            let (_,response)=try await get(url,limit:200_000)
            guard (300...399).contains(response.statusCode),let location=response.value(forHTTPHeaderField:"Location"),let next=URL(string:location,relativeTo:url)?.absoluteURL.absoluteString,LinkPolicy.allowed(next) else{throw LineDrawError.message("連結尚無法解析，請稍後同步。")}
            if let canonical=LinkPolicy.canonical(next){return canonical};current=next
        };throw LineDrawError.message("抽選連結重新導向過多。")
    }
    public func fetch() async throws -> [Draw] {
        let (data,response)=try await get(CatalogParser.sourceURL,limit:2_000_000)
        guard response.statusCode==200,let html=String(data:data,encoding:.utf8) else{throw LineDrawError.message("同步失敗，保留前次清單。")}
        var rows=try CatalogParser.parse(html)
        // Four concurrent redirects, in original source order. Failed resolutions remain visible but cannot run.
        var resolved:[String:String]=[:];let unique=Array(Set(rows.map(\.url))).sorted()
        for offset in stride(from:0,to:unique.count,by:4){try Task.checkCancellation();let chunk=Array(unique[offset..<min(offset+4,unique.count)])
            await withTaskGroup(of:(String,String?).self){group in
                for url in chunk { group.addTask{ (url,try? await self.resolve(url)) } }
                for await (url,value) in group { if let value{resolved[url]=value} }
            }
        }
        try Task.checkCancellation()
        for i in rows.indices {if let url=resolved[rows[i].url]{rows[i].canonicalURL=url;rows[i].activityKey=LinkPolicy.key(url)}}
        let grouped=Dictionary(grouping:rows,by:\.activityKey)
        guard grouped.values.allSatisfy({Set($0.map(\.store)).count==1}) else{throw LineDrawError.message("同一活動的店家資料衝突。")}
        return rows
    }
}
public enum TestCatalog {
    // Only these built-in IDs are upgraded automatically; user-imported catalogs stay intact.
    public static let previousBuiltInIDs=Set(["01M34QPHTDYX6TQ5F0M5TKP5J7","01M34QQ7QZNTMR8M7ADSWXY7AW","01M34QQXZ27VBQPSY134CD6FG4","01M34QRHHTGYP0NZ594RCR9Z6T","01M34QS2Y5Z75XA9E8ED6SWBD4"].map{"test:"+$0})
    public static let previousBuiltInCatalogs=[
        previousBuiltInIDs,
        Set(["01M3NR6Y99ART5N0WJ1XZVGZDP","01M3NR7CBXE30DDE4GGQB4QCGA","01M3NR7QB9JFTEQAMAC38NZCA1","01M3NR81J75SFMQWHRKGHBJ1H0","01M3NR8F5E3B3AR40SS9TM5SED"].map{"test:"+$0}),
        Set(["01M3NYWYRQS7E5TJSH4AVFBVZT","01M3NYXBT8TATAW522BZF2THQ6","01M3NYXQJXB6YQAKYNPF39J62K","01M3NYY4GA9FE3PAQBVQA26X3S","01M3NYYGJ71H8JH7HM5WG0JCFY"].map{"test:"+$0}),
        Set(["01M3P1WYDKQCAEXNS2ZH6J1VMN","01M3P1XATPMQ2H6488HC8XVAQ4","01M3P1XMQAXHWFWDZQ8EVFJ6WQ","01M3P1Y0D3K8KJZWXXZ8NM8A0S","01M3P1YEB564HSFGP2FT72RT3N"].map{"test:"+$0})
    ]
    public static func five() -> [Draw] {
        let pairs=[("Qd5hJVq","01M3PFR9C1EN49S8949WFHDPGA"),("QGhOsnX","01M3PFRTX70E47T6BY81FAZZSR"),("XnMZVTX","01M3PFSB92G86W4Y7KWR01DNQZ"),("W0zn6z4","01M3PFSRSA9210CX5B1VA6PH1T"),("yz7xFEWc","01M3PFT6EBNAC6XZ8J4BCBHKNX")]
        // Enabled from this catalog update; user confirmed expiry on 10/31 (Taipei).
        // November 1 at midnight is exclusive, so the whole final minute remains usable.
        let period=try! DrawSchedule.parse("抽選：2026/09/29 00:00～2026/11/01 00:00")
        return pairs.enumerated().map { i,p in let url="https://liff.line.me/1654883387-DxN9w07M/c/\(p.1)";return Draw(id:"test:\(p.1)",activityKey:LinkPolicy.key(url),store:"陀螺獵人 Beyblade Hunter",city:"實機測試",product:"抽選測試 · 第 \(i+1) 筆",url:"https://lin.ee/\(p.0)",canonicalURL:url,timeLabel:"測試開放至 2026/10/31 23:59（台北時間）",startsAt:period.0,endsAt:period.1,ordinal:i,area:.test) }
    }
    public static func demo(now:Date=Date()) -> [Draw] {
        let names=["BX-45 武士聖劍 2-70L","UX-12 幻影雷龍 9-70P","CX-05 魔導權杖 F 1-70L","BX-44 三角龍重擊 2-60L","UX-11 衝擊飛龍 9-60LR","CX-03 英勇烈焰 D 3-85B"]
        return names.enumerated().map{i,name in let url="https://liff.line.me/linedraw-fixture/c/demo\(i)";return Draw(id:"demo:\(i)",activityKey:LinkPolicy.key(url),store:i<3 ? "陀螺基地 · 台北店":"旋轉日常 · 台中店",city:i<3 ? "台北市":"台中市",product:name,url:url,canonicalURL:url,timeLabel:"離線示範資料，不會開啟 LINE",startsAt:now.addingTimeInterval(i==3 ? 3600:-86400),endsAt:i==4 ? nil:now.addingTimeInterval(86400),ordinal:i,area:.demo)}
    }
}
