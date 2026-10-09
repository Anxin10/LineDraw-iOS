import XCTest
@testable import LineDrawCore
final class CatalogSourceTests:XCTestCase {
    func testSyncStatusForFreshLegacyAndSourceSpecificSnapshots()throws {
        var snapshot=DatabaseSnapshot()
        XCTAssertEqual(snapshot.syncStatus(for:.funbox).summary,"尚未同步")
        XCTAssertEqual(snapshot.syncStatus(for:.beybladeHunter).summary,"尚未同步")
        snapshot.syncSummary="舊 Funbox 摘要";snapshot.lastSync=Date(timeIntervalSince1970:100)
        // Simulate an existing installation that predates source-specific fields.
        snapshot=try WireJSON.decoder().decode(DatabaseSnapshot.self,from:WireJSON.encoder().encode(snapshot))
        XCTAssertEqual(snapshot.syncStatus(for:.funbox).summary,"舊 Funbox 摘要")
        XCTAssertEqual(snapshot.syncStatus(for:.funbox).lastSync,snapshot.lastSync)
        XCTAssertNil(snapshot.syncStatus(for:.beybladeHunter).lastSync)
        snapshot.catalogSync=[CatalogSource.beybladeHunter.rawValue:CatalogSync(lastSync:nil,summary:"獵人摘要")]
        XCTAssertEqual(snapshot.syncStatus(for:.funbox).summary,"舊 Funbox 摘要")
        XCTAssertEqual(snapshot.syncStatus(for:.beybladeHunter).summary,"獵人摘要")
        snapshot.catalogSync?[CatalogSource.funbox.rawValue]=CatalogSync(lastSync:nil,summary:"新版摘要")
        XCTAssertEqual(snapshot.syncStatus(for:.funbox).summary,"新版摘要")
        XCTAssertNil(snapshot.syncStatus(for:.funbox).lastSync)
    }
    func testSourceIsolationAndSharedRecords()throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:file)}
        var db=try LocalDatabase(file:file)
        var fun=TestCatalog.five()[0];fun.area = .website;fun.id="funbox-one"
        var hunter=fun;hunter.id=CatalogSource.hunterPrefix+"1"
        try db.merge([fun],area:.website)
        try db.merge([hunter],area:.website,source:.beybladeHunter)
        XCTAssertEqual(db.snapshot.draws.filter{!$0.archived}.count,2)
        try db.manual(fun,profile:"default")
        XCTAssertEqual(db.records(profile:"default",area:.website)[hunter.activityKey]?.status,"MANUAL")
        try db.merge([],area:.website,source:.beybladeHunter)
        XCTAssertFalse(db.snapshot.draws.first{$0.id==fun.id}!.archived)
        XCTAssertTrue(db.snapshot.draws.first{$0.id==hunter.id}!.archived)
        XCTAssertThrowsError(try db.merge([fun],area:.website,source:.beybladeHunter))
        XCTAssertThrowsError(try db.merge([],area:.website))
        XCTAssertNotNil(db.snapshot.catalogSync?[CatalogSource.beybladeHunter.rawValue])
    }
    func testOldSnapshotDecodesWithoutSourceFields()throws {
        let data=try WireJSON.encoder().encode(DatabaseSnapshot())
        var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        object.removeValue(forKey:"selectedCatalog");object.removeValue(forKey:"catalogSync")
        let old=try WireJSON.decoder().decode(DatabaseSnapshot.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(old.selectedCatalog)
    }
    func testHunterStrictEnvelope()throws {
        XCTAssertEqual(try BeybladeHunterParser.parse("{\"draws\":[]}").count,0)
        XCTAssertThrowsError(try BeybladeHunterParser.parse("[]"))
        XCTAssertThrowsError(try BeybladeHunterParser.parse("{}"))
        let row=#"{"id":1,"line_url":"https://lin.ee/abc","city":"台北市","store_name":"店家","product_name":"商品","start_time":"2026-10-01 00:00:00","end_time":"2026-10-31 23:59:00"}"#
        let rows=try BeybladeHunterParser.parse("{\"draws\":[\(row)]}")
        XCTAssertTrue(CatalogSource.beybladeHunter.owns(rows[0]))
        XCTAssertFalse(CatalogSource.funbox.owns(rows[0]))
        XCTAssertThrowsError(try BeybladeHunterParser.parse("{\"draws\":[\(row),\(row)]}"))
    }
}
