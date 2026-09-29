import XCTest
@testable import LineDrawCore

final class TestCatalogUpgradeTests:XCTestCase {
    func testOctoberDeadlineIncludesLastMinuteInTaipei() {
        let row=TestCatalog.five()[0]
        XCTAssertTrue(row.runnable(at:WireJSON.parseDate("2026-10-31T15:59:59Z")!))
        XCTAssertEqual(row.eligibility(at:WireJSON.parseDate("2026-10-31T16:00:00Z")!),.expired)
    }
    func testLatestLinksKeepSuppliedOrderAndUpgradePreviousFive()throws {
        XCTAssertEqual(TestCatalog.five().map(\.url),["https://lin.ee/Qd5hJVq","https://lin.ee/QGhOsnX","https://lin.ee/XnMZVTX","https://lin.ee/W0zn6z4","https://lin.ee/yz7xFEWc"])
        for previous in TestCatalog.previousBuiltInCatalogs {
            var db=try database()
            let old=previous.sorted().enumerated().map{i,id->Draw in
                let url="https://liff.line.me/1654883387-DxN9w07M/c/"+id.dropFirst("test:".count)
                return Draw(id:id,activityKey:LinkPolicy.key(url),store:"測試店",city:"實機測試",product:"上一輪",url:url,canonicalURL:url,startsAt:nil,endsAt:nil,ordinal:i,area:.test)
            }
            try db.merge(old,area:.test);try db.manual(old[0],profile:"primary")
            let records=db.snapshot.records
            try db.refreshBuiltInTests()
            XCTAssertEqual(db.snapshot.draws.filter{!$0.archived},TestCatalog.five())
            XCTAssertEqual(db.snapshot.records,records)
            XCTAssertEqual(Set(db.snapshot.draws.filter(\.archived).map(\.id)),previous)
        }
    }
    private func database()throws->LocalDatabase {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock{try? FileManager.default.removeItem(at:folder)}
        return try LocalDatabase(file:folder.appendingPathComponent("state.json"))
    }
    func testUpgradeArchivesOldCouponsAndPreservesHistoryAcrossRestart()throws {
        var db=try database()
        let old=TestCatalog.previousBuiltInIDs.sorted().enumerated().map{i,id->Draw in
            let url="https://liff.line.me/1654883387-DxN9w07M/c/"+id.dropFirst("test:".count)
            return Draw(id:id,activityKey:LinkPolicy.key(url),store:"測試店",city:"實機測試",product:"原活動",url:url,canonicalURL:url,startsAt:nil,endsAt:nil,ordinal:i,area:.test)
        }
        let website=try CatalogParser.parse("<div id='page-draws'><div class='draw-store'><b class='draw-store-name'>網站店</b><div class='draw-item' data-draw-id='web' data-draw-href='https://lin.ee/website'><span class='draw-product'>商品</span></div></div></div>")
        try db.merge(old,area:.test)
        try db.merge(website,area:.website)
        try db.manual(old[0],profile:"primary")
        db=try LocalDatabase(file:db.file) // Compare the persisted timestamp precision on both sides.
        let originalRecords=db.snapshot.records,originalOutbox=db.snapshot.bridgeOutbox.map(\.id)
        try db.refreshBuiltInTests()
        db=try LocalDatabase(file:db.file)
        XCTAssertEqual(db.snapshot.draws.filter{$0.area == .test && !$0.archived},TestCatalog.five())
        XCTAssertEqual(Set(db.snapshot.draws.filter{$0.area == .test && $0.archived}.map(\.id)),TestCatalog.previousBuiltInIDs)
        XCTAssertEqual(db.snapshot.draws.filter{$0.area == .website},website)
        XCTAssertEqual(db.snapshot.records,originalRecords)
        XCTAssertEqual(db.snapshot.bridgeOutbox.map(\.id),originalOutbox)
        XCTAssertTrue(TestCatalog.five().allSatisfy{db.records(profile:"primary",area:.test)[$0.activityKey]==nil})
        let saved=try Data(contentsOf:db.file)
        try db.refreshBuiltInTests()
        XCTAssertEqual(try Data(contentsOf:db.file),saved)
    }
    func testFreshInstallSeedsNewCatalogButCustomImportIsNotReplaced()throws {
        var db=try database()
        try db.refreshBuiltInTests()
        XCTAssertEqual(db.snapshot.draws,TestCatalog.five())
        var custom=TestCatalog.five()[0]
        custom.id="test:"+custom.activityKey // JSON importer identity, including if the URL is a built-in coupon.
        custom.timeLabel="使用者匯入";custom.startsAt=Date(timeIntervalSince1970:100);custom.endsAt=Date(timeIntervalSince1970:200)
        try db.merge([custom],area:.test)
        let saved=try Data(contentsOf:db.file)
        try db.refreshBuiltInTests()
        XCTAssertEqual(try Data(contentsOf:db.file),saved)
        XCTAssertEqual(db.snapshot.draws.filter{!$0.archived},[custom])
    }
}
