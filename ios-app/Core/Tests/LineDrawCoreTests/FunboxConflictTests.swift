import XCTest
@testable import LineDrawCore
final class FunboxConflictTests:XCTestCase {
    func testConflictDoesNotBlockOtherRowsOrRestoreCachedLink()throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:file)}
        var db=try LocalDatabase(file:file)
        var a=TestCatalog.five()[0];a.area = .website;a.id="a";a.store="樹林"
        var b=a;b.id="b";b.store="新竹"
        var c=TestCatalog.five()[1];c.area = .website;c.id="c"
        try db.merge([a,b,c],area:.website)
        try db.manual(a,profile:"default")
        let reviewed=CatalogConflictPolicy.review([a,b,c])
        XCTAssertEqual(reviewed.count,3)
        XCTAssertNotNil(reviewed[0].syncIssue)
        XCTAssertNil(reviewed[0].canonicalURL)
        XCTAssertFalse(reviewed[0].runnable(at:a.startsAt!.addingTimeInterval(1)))
        XCTAssertNil(reviewed[2].syncIssue)
        XCTAssertEqual(reviewed[2].canonicalURL,c.canonicalURL)
        try db.merge(reviewed,area:.website)
        XCTAssertNil(db.snapshot.draws.first{$0.id=="a"}!.canonicalURL)
        XCTAssertTrue(db.snapshot.syncSummary.contains("待確認 2 筆"))
        XCTAssertEqual(db.records(profile:"default",area:.website)[a.activityKey]?.status,"MANUAL")
        try db.merge(CatalogConflictPolicy.review([a,c]),area:.website)
        XCTAssertNil(db.snapshot.draws.first{$0.id=="a"}!.syncIssue)
        XCTAssertNotNil(db.snapshot.draws.first{$0.id=="a"}!.canonicalURL)
    }
    func testLiveConflictInspection()async throws {
        guard let path=ProcessInfo.processInfo.environment["LINEDRAW_CONFLICT_STATE"] else{throw XCTSkip("Optional source integration")}
        let state=try WireJSON.decoder().decode(DatabaseSnapshot.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        var rows=try CatalogParser.parse(String(contentsOfFile:ProcessInfo.processInfo.environment["LINEDRAW_LIVE_SOURCE"]!,encoding:.utf8))
        let known=CatalogResolutionCache.build(state.draws)
        for i in rows.indices {
            if let canonical=known[rows[i].url] {rows[i].canonicalURL=canonical;rows[i].activityKey=LinkPolicy.key(canonical,store:rows[i].store,period:rows[i].timeLabel)}
        }
        let reviewed=CatalogConflictPolicy.review(rows)
        XCTAssertEqual(reviewed.count,431)
        XCTAssertEqual(reviewed.filter{$0.syncIssue != nil}.count,4)
        XCTAssertTrue(reviewed.filter{$0.syncIssue != nil}.allSatisfy{$0.canonicalURL==nil})
    }
}
