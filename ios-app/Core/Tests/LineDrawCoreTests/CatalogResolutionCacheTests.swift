import XCTest
@testable import LineDrawCore
final class CatalogResolutionCacheTests:XCTestCase {
    func testRepeatedArchivedAndCurrentURLsAreSafe() {
        let first=TestCatalog.five()[0]
        var old=first;old.archived=true
        XCTAssertEqual(CatalogResolutionCache.build([first,old])[first.url],first.canonicalURL)
    }
    func testConflictingMappingsAreNeverReusedRegardlessOfOrder() {
        let first=TestCatalog.five()[0]
        var other=TestCatalog.five()[1];other.url=first.url
        XCTAssertNotEqual(first.canonicalURL,other.canonicalURL)
        for rows in [[first,other,first],[other,first,other]] {
            XCTAssertNil(CatalogResolutionCache.build(rows)[first.url])
        }
    }
    func testInvalidAndMissingMappingsDoNotOverrideValidEntry() {
        let first=TestCatalog.five()[0]
        var invalid=first;invalid.canonicalURL="not-a-coupon"
        var missing=first;missing.canonicalURL=nil
        XCTAssertEqual(CatalogResolutionCache.build([first,invalid,missing])[first.url],first.canonicalURL)
    }
}
