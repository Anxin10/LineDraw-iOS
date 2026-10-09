import XCTest
@testable import LineDrawCore

final class CatalogShelfSaleTests: XCTestCase {
    private let notice = "<div class=\"draw-item\"><div class=\"draw-product\">BX-37 豪華組（採取上架販售）</div></div>"
    private let draw = "<div class=\"draw-item\" data-draw-id=\"one\" data-draw-href=\"https://lin.ee/abc\"><div class=\"draw-product\">UX-01 蒼龍爆刃</div></div>"
    private func page(_ rows: String) -> String {
        "<div id=\"page-draws\"><div class=\"draw-store\" data-draw-city=\"新竹市\"><div class=\"draw-store-name\">Funbox 新竹巨城店</div><div class=\"draw-start\">抽選/購買時間：2026/10/02～2026/10/03（貼文未註明起始時間）</div>\(rows)</div></div>"
    }
    func testShelfSaleNoticeDoesNotBlockDrawsOrInventTimes() throws {
        let rows = try CatalogParser.parse(page(notice + draw))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].product, "UX-01 蒼龍爆刃")
        XCTAssertEqual(rows[0].ordinal, 0)
        XCTAssertNil(rows[0].startsAt)
        XCTAssertNil(rows[0].endsAt)
        XCTAssertFalse(rows[0].runnable(at: Date()))
    }
    func testMalformedRowsStillRejectPage() {
        XCTAssertThrowsError(try CatalogParser.parse(page(notice.replacingOccurrences(of: "（採取上架販售）", with: "") + draw)))
        XCTAssertThrowsError(try CatalogParser.parse(page(notice.replacingOccurrences(of: "class=\"draw-item\"", with: "class=\"draw-item\" data-draw-id=\"broken\"") + draw)))
        XCTAssertThrowsError(try CatalogParser.parse(page(draw + draw)))
        XCTAssertThrowsError(try CatalogParser.parse(page(draw.replacingOccurrences(of: "https://lin.ee/abc", with: "https://example.com/abc"))))
        XCTAssertThrowsError(try CatalogParser.parse(page(notice)))
    }
    func testMissingDOMIDWithValidLinkHasStableIdentity()throws {
        let missing=draw.replacingOccurrences(of:" data-draw-id=\"one\"",with:"")
        let first=try CatalogParser.parse(page(missing))[0]
        let reordered=try CatalogParser.parse(page(draw.replacingOccurrences(of:"https://lin.ee/abc",with:"https://lin.ee/other")+missing))[1]
        XCTAssertEqual(first.id,reordered.id)
        XCTAssertEqual(first.url,"https://lin.ee/abc")
        XCTAssertTrue(first.id.hasPrefix("derived:"))
        XCTAssertThrowsError(try CatalogParser.parse(page(missing+missing)))
        XCTAssertThrowsError(try CatalogParser.parse(page(missing.replacingOccurrences(of:"https://lin.ee/abc",with:""))))
        XCTAssertThrowsError(try CatalogParser.parse(page(missing.replacingOccurrences(of:"https://lin.ee/abc",with:"https://example.com"))))
    }
    func testLatestSourceSnapshot()throws {
        guard let path=ProcessInfo.processInfo.environment["LINEDRAW_LIVE_SOURCE"] else{throw XCTSkip("Optional live source check")}
        let rows=try CatalogParser.parse(String(contentsOfFile:path,encoding:.utf8))
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(Set(rows.map(\.id)).count,rows.count)
        XCTAssertTrue(rows.allSatisfy{LinkPolicy.allowed($0.url)})
        print("Live Funbox parsed: \(rows.count) rows; derived IDs: \(rows.filter{$0.id.hasPrefix("derived:")}.count)")
    }
    func testDownloadedSourceSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["LINEDRAW_SOURCE_SNAPSHOT"] else {
            throw XCTSkip("Optional check of the 2026-10-02 source snapshot")
        }
        let rows = try CatalogParser.parse(String(contentsOfFile: path, encoding: .utf8))
        XCTAssertEqual(rows.count, 1289)
        XCTAssertEqual(Set(rows.map(\.store)).count, 76)
        XCTAssertEqual(rows.filter { $0.store == "Funbox 新竹巨城店" }.count, 21)
        XCTAssertEqual(rows.map(\.ordinal), Array(rows.indices))
    }
}
