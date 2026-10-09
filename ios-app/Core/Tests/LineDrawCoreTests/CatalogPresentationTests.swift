import XCTest
@testable import LineDrawCore
final class CatalogPresentationTests:XCTestCase {
    func testSelectionProjectionPreservesOrderFiltersAndProfileScope() throws {
        let now=Date();var snapshot=DatabaseSnapshot();snapshot.draws=TestCatalog.demo(now:now)
        let first=snapshot.draws[0]
        snapshot.records[LocalDatabase.scope(profile:snapshot.settings.profile,area:.demo)+"\n"+first.activityKey]=ParticipationRecord(id:first.activityKey,product:first.product,store:first.store,status:"SUBMITTED",evidence:"test")
        var filter=CatalogFilter();filter.cities=["台北市"]
        let view=CatalogPresentation(snapshot:snapshot,area:.demo,filter:filter,now:now)
        XCTAssertEqual(view.all.map(\.id),snapshot.draws.sorted{$0.ordinal<$1.ordinal}.map(\.id))
        XCTAssertTrue(view.visible.allSatisfy{$0.city=="台北市"})
        XCTAssertFalse(view.runnable.contains{$0.id==first.id})
        snapshot.settings.profile="another"
        XCTAssertTrue(CatalogPresentation(snapshot:snapshot,area:.demo,filter:filter,now:now).runnable.contains{$0.id==first.id})
        XCTAssertTrue(CatalogPresentation(snapshot:snapshot,area:.website,filter:filter,now:now).records.isEmpty)
    }
    func testLargeCatalogSelectionUsesPreparedRows() {
        let now=Date();var snapshot=DatabaseSnapshot();let sample=TestCatalog.demo(now:now)[0]
        snapshot.draws=(0..<1500).map{i in var d=sample;d.id="row-\(i)";d.activityKey="key-\(i)";d.ordinal=i;return d}
        for d in snapshot.draws.prefix(400){snapshot.records[LocalDatabase.scope(profile:snapshot.settings.profile,area:.demo)+"\n"+d.activityKey]=ParticipationRecord(id:d.activityKey,product:d.product,store:d.store,status:"SUBMITTED",evidence:"test")}
        let began=Date();let view=CatalogPresentation(snapshot:snapshot,area:.demo,filter:CatalogFilter(),now:now)
        var selected=Set<String>()
        for row in view.runnable.prefix(100){selected.insert(row.id);XCTAssertEqual(view.runnable.filter{selected.contains($0.id)}.count,selected.count)}
        XCTAssertEqual(view.runnable.count,1100)
        print("Prepare 1500 rows and select 100: \(Date().timeIntervalSince(began))s")
    }
}
