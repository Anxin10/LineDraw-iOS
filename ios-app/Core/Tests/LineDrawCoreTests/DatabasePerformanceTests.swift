import XCTest
@testable import LineDrawCore

final class DatabasePerformanceTests: XCTestCase {
    func testUnsortedPersistenceKeepsIdenticalJSONValues()throws{
        var snapshot=DatabaseSnapshot();snapshot.draws=TestCatalog.five()
        snapshot.settings.batchLookupMode="compact"
        snapshot.records["a"]=ParticipationRecord(id:"a",product:"測試",store:"店家",status:"SUBMIT_INTENT",evidence:"durable",updatedAt:Date(timeIntervalSince1970:1790912000.125))
        let sorted=try JSONSerialization.jsonObject(with:WireJSON.encoder().encode(snapshot)) as! NSDictionary
        let unsorted=try JSONSerialization.jsonObject(with:WireJSON.encoder(sortedKeys:false).encode(snapshot)) as! NSDictionary
        XCTAssertEqual(sorted,unsorted)
        let roundTrip=try WireJSON.decoder().decode(DatabaseSnapshot.self,from:WireJSON.encoder(sortedKeys:false).encode(snapshot))
        XCTAssertEqual(roundTrip.records,snapshot.records);XCTAssertEqual(roundTrip.draws.map(\.activityKey),snapshot.draws.map(\.activityKey))
        XCTAssertEqual(roundTrip.settings.batchLookupMode,"compact")
    }
    func testDateMemoizationPreservesDistinctDatesBeyondCacheLimit()throws{
        let encoder=WireJSON.encoder()
        let dates=(0..<4100).map{Date(timeIntervalSince1970:1790912000+Double($0)/10)}
        let values=try JSONDecoder().decode([String].self,from:encoder.encode(dates))
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        XCTAssertEqual(values,dates.map{formatter.string(from:$0)})
        let later=Date(timeIntervalSince1970:1790920000.125)
        XCTAssertEqual(try JSONDecoder().decode(String.self,from:encoder.encode(later)),formatter.string(from:later))
    }
    func testLargeCatalogRecordWritePreservesWireDatesAndReloads() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        var db=try LocalDatabase(file:file)
        let rows=(0..<1300).map { i -> Draw in
            var row=TestCatalog.demo()[0];row.id="large-\(i)";row.activityKey="large-\(i)";return row
        }
        try db.merge(rows,area:.demo)
        let legacy=JSONEncoder();legacy.outputFormatting=[.sortedKeys]
        legacy.dateEncodingStrategy = .custom { date,encoder in
            var container=encoder.singleValueContainer();try container.encode(WireJSON.date(date))
        }
        let before=Date();let oldBytes=try legacy.encode(db.snapshot)
        let legacySeconds=Date().timeIntervalSince(before)
        let after=Date();let newBytes=try WireJSON.encoder().encode(db.snapshot)
        print("Catalog encoding legacy: \(legacySeconds)s; optimized: \(Date().timeIntervalSince(after))s")
        XCTAssertEqual(newBytes,oldBytes)
        let start=Date()
        try db.manual(rows[0],profile:"default")
        print("Large catalog durable record write: \(Date().timeIntervalSince(start)) seconds")
        let reloaded=try LocalDatabase(file:file)
        XCTAssertEqual(reloaded.snapshot.draws.count,1300)
        XCTAssertEqual(reloaded.records(profile:"default",area:.demo)[rows[0].activityKey]?.status,"MANUAL")
        XCTAssertEqual(reloaded.snapshot.draws[0].startsAt!.timeIntervalSince1970,rows[0].startsAt!.timeIntervalSince1970,accuracy:0.001)
        let date=Date(timeIntervalSince1970:1790912000.125)
        XCTAssertEqual(String(data:try WireJSON.encoder().encode(date),encoding:.utf8),"\""+WireJSON.date(date)+"\"")
    }
}
