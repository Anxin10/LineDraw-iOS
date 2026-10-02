import XCTest
@testable import LineDrawCore

final class CatalogSourceTests:XCTestCase{
    private let html="<section id='page-draws'><div class='draw-store' data-draw-city='台北市'><b class='draw-store-name'>測試店</b><div class='draw-start'>抽選：2026/10/02 11:00~2026/10/03 21:00</div><div class='draw-items'>ROWS</div></div></section>"
    private let valid="<div class='draw-item draw-item-clickable' data-draw-id='one' data-draw-href='https://liff.line.me/test/c/one'><b class='draw-product'>商品 A</b></div>"
    private let sales="<div class='draw-item'><b class='draw-product'>BX-37（採取上架販售）</b></div>"
    private var row:[String:Any]{["id":42,"line_url":"https://liff.line.me/test/c/one","city":"台北市","store_name":"測試店","product_name":"商品 A","start_time":"2026-10-02 11:00:00","end_time":"2026-10-03 21:00:00"]}
    private func payload(_ rows:[[String:Any]])throws->String{String(data:try JSONSerialization.data(withJSONObject:["draws":rows]),encoding:.utf8)!}
    private func website()throws->[Draw]{try CatalogParser.parse(html.replacingOccurrences(of:"ROWS",with:valid))}
    private func hunter()throws->[Draw]{try CatalogSource.beybladeHunter.parse(payload([row]))}
    private func database()throws->LocalDatabase{let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);addTeardownBlock{try? FileManager.default.removeItem(at:dir)};return try LocalDatabase(file:dir.appendingPathComponent("state.json"))}
    func testDisplayOnlySalesAndEntireDisplayStoreAreSkipped()throws{
        let mixed=html.replacingOccurrences(of:"ROWS",with:sales+valid+sales)
        let salesOnly=html.replacingOccurrences(of:"ROWS",with:sales)
        let rows=try CatalogParser.parse(mixed+salesOnly)
        XCTAssertEqual(rows.count,1);XCTAssertEqual(rows[0].product,"商品 A");XCTAssertEqual(rows[0].ordinal,0)
    }
    func testBrokenActionRowsStillRejectEntirePage(){
        for marker in ["data-draw-id='bad'","data-draw-href='https://lin.ee/bad'","onclick='openDraw()'","onkeydown='openDraw()'","role='link'","class='draw-item draw-item-clickable'"]{
            let broken="<div \(marker) \(marker.hasPrefix("class=") ? "":"class='draw-item'")><b class='draw-product'>損壞</b></div>"
            XCTAssertThrowsError(try CatalogParser.parse(html.replacingOccurrences(of:"ROWS",with:valid+broken)),marker)
        }
        XCTAssertThrowsError(try CatalogParser.parse(html.replacingOccurrences(of:"ROWS",with:sales)))
        XCTAssertThrowsError(try CatalogParser.parse(html.replacingOccurrences(of:"ROWS",with:valid+valid)))
    }
    func testHunterUsesTaipeiTimesAndCanonicalSharedIdentity()throws{
        let h=try hunter()[0],f=try website()[0]
        XCTAssertEqual(h.startsAt,WireJSON.parseDate("2026-10-02T03:00:00Z"));XCTAssertEqual(h.endsAt,WireJSON.parseDate("2026-10-03T13:00:00Z"))
        XCTAssertEqual(h.activityKey,f.activityKey);XCTAssertNotEqual(h.id,f.id)
        XCTAssertTrue(CatalogSource.beybladeHunter.owns(h));XCTAssertFalse(CatalogSource.funbox.owns(h))
        XCTAssertEqual(h.eligibility(at:h.startsAt!),.ready);XCTAssertEqual(h.eligibility(at:h.endsAt!),.expired)
    }
    func testHunterEmptyAndUnknownTimeAreValid()throws{
        XCTAssertTrue(try CatalogSource.beybladeHunter.parse("{\"draws\":[]}").isEmpty)
        var r=row;r.removeValue(forKey:"start_time");r["end_time"]=NSNull()
        let d=try BeybladeHunterParser.parse(payload([r]))[0];XCTAssertEqual(d.eligibility(),.unknown)
    }
    func testHunterMalformedDatesIDsAndLinksRejectWholePayload()throws{
        for (key,value) in [("id",true as Any),("id",0),("id","01"),("id","9223372036854775808"),("start_time","2026-02-30 11:00:00"),("start_time",42),("end_time","2026-10-01 21:00:00"),("line_url","https://evil.test/draw"),("store_name","")]{
            var r=row;r[key]=value;XCTAssertThrowsError(try BeybladeHunterParser.parse(payload([r])),"\(key)=\(value)")
        }
        XCTAssertThrowsError(try BeybladeHunterParser.parse(payload([row,row])))
        XCTAssertThrowsError(try BeybladeHunterParser.parse("{}"))
    }
    func testHunterNumericAndStringIDsPreserveOrder()throws{
        var second=row;second["id"]="43";second["product_name"]="商品 B"
        let rows=try BeybladeHunterParser.parse(payload([row,second]));XCTAssertEqual(rows.map(\.product),["商品 A","商品 B"]);XCTAssertEqual(rows.map(\.ordinal),[0,1])
    }
    func testLegacySnapshotLoadsWithoutSourceFields()throws{
        var db=try database();let rows=try website();try db.merge(rows,area:.website)
        try db.manual(rows[0],profile:"p")
        var json=try JSONSerialization.jsonObject(with:Data(contentsOf:db.file)) as! [String:Any]
        json.removeValue(forKey:"selectedCatalog");json.removeValue(forKey:"catalogSync")
        try JSONSerialization.data(withJSONObject:json).write(to:db.file)
        let reopened=try LocalDatabase(file:db.file)
        XCTAssertEqual(reopened.snapshot.catalog,.funbox);XCTAssertNotNil(reopened.snapshot.syncInfo(for:.funbox).lastSync)
        XCTAssertEqual(reopened.records(profile:"p",area:.website)[rows[0].activityKey]?.status,"MANUAL")
    }
    func testSwitchPersistsSourceRetainsBothCachesAndSharedCompletion()throws{
        var db=try database();let f=try website(),h=try hunter()
        let first=Date(timeIntervalSince1970:1),second=Date(timeIntervalSince1970:2)
        try db.merge(f,area:.website,now:first);try db.manual(f[0],profile:"p")
        try db.merge(h,area:.website,source:.beybladeHunter,selectSource:true,now:second)
        let reopened=try LocalDatabase(file:db.file)
        XCTAssertEqual(reopened.snapshot.catalog,.beybladeHunter);XCTAssertEqual(reopened.snapshot.draws.filter{!$0.archived}.count,2)
        XCTAssertEqual(reopened.snapshot.syncInfo(for:.funbox).lastSync,first);XCTAssertEqual(reopened.snapshot.syncInfo(for:.beybladeHunter).lastSync,second)
        XCTAssertEqual(reopened.records(profile:"p",area:.website)[h[0].activityKey]?.status,"MANUAL")
        XCTAssertTrue(reopened.records(profile:"p",area:.test).isEmpty)
    }
    func testEmptyHunterArchivesOnlyItsCacheAndPreservesHistory()throws{
        var db=try database();let f=try website(),h=try hunter();try db.merge(f,area:.website);try db.merge(h,area:.website,source:.beybladeHunter)
        try db.manual(h[0],profile:"p");try db.merge([],area:.website,source:.beybladeHunter,selectSource:true)
        XCTAssertEqual(db.snapshot.draws.first{$0.id==f[0].id}?.archived,false)
        XCTAssertEqual(db.snapshot.draws.first{$0.id==h[0].id}?.archived,true)
        XCTAssertEqual(db.records(profile:"p",area:.website)[h[0].activityKey]?.status,"MANUAL")
    }
    func testRejectedSwitchLeavesFileAndSourceUnchanged()throws{
        var db=try database();try db.merge(website(),area:.website)
        let before=try Data(contentsOf:db.file)
        XCTAssertThrowsError(try db.merge(website(),area:.website,source:.beybladeHunter,selectSource:true))
        XCTAssertThrowsError(try db.merge([],area:.website,source:.funbox,selectSource:true))
        XCTAssertEqual(db.snapshot.catalog,.funbox);XCTAssertEqual(try Data(contentsOf:db.file),before)
    }
    func testCompanionReceivesSelectedSource()throws{
        let request=CompanionStart(profile:"p",area:.website,rows:try hunter(),selectedIDs:[],records:[],filter:CatalogFilter(),autoFriend:true,autoContinue:true,catalogSource:.beybladeHunter)
        let data=try WireJSON.encoder().encode(request),json=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        XCTAssertEqual(json["catalogSource"] as? String,"beybladehunter")
    }
    func testCapturedLiveSnapshots()throws{
        guard let dir=ProcessInfo.processInfo.environment["LINEDRAW_CATALOG_SNAPSHOTS"] else{throw XCTSkip("僅在提供本機來源快照時執行")}
        let f=try CatalogParser.parse(String(contentsOfFile:dir+"/funbox.body",encoding:.utf8)),h=try BeybladeHunterParser.parse(String(contentsOfFile:dir+"/hunter.body",encoding:.utf8))
        XCTAssertEqual(f.count,1289);XCTAssertEqual(h.count,1287);XCTAssertEqual(Set(f.map(\.store)).count,76)
    }
    func testLiveCatalogNetworkReadOnly()async throws{
        guard ProcessInfo.processInfo.environment["LINEDRAW_LIVE_CATALOGS"]=="1" else{throw XCTSkip("需明確啟用唯讀連線測試")}
        for source in CatalogSource.allCases{
            let start=Date(),rows=try await CatalogNetwork().fetch(source:source)
            XCTAssertGreaterThan(rows.count,1000);XCTAssertTrue(rows.allSatisfy(source.owns));XCTAssertGreaterThan(rows.filter{$0.canonicalURL != nil}.count,rows.count*9/10)
            print("LIVE_CATALOG \(source.rawValue) rows=\(rows.count) resolved=\(rows.filter{$0.canonicalURL != nil}.count) seconds=\(Date().timeIntervalSince(start))")
        }
    }
}
