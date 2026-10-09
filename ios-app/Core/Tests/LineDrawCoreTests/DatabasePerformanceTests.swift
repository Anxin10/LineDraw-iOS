import XCTest
@testable import LineDrawCore

final class DatabasePerformanceTests: XCTestCase {
    private func assertFullSnapshot(_ db:LocalDatabase,file:URL)throws{
        let persisted=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! NSDictionary
        let expectedBytes=try WireJSON.encoder(sortedKeys:false).encode(db.snapshot)
        let expected=try JSONSerialization.jsonObject(with:expectedBytes) as! NSDictionary
        XCTAssertEqual(persisted,expected)
        // Compare against the existing wire precision, including millisecond dates.
        let expectedReload=try WireJSON.decoder().decode(DatabaseSnapshot.self,from:expectedBytes)
        XCTAssertEqual(try LocalDatabase(file:file).snapshot.draws,expectedReload.draws)
        XCTAssertEqual(try LocalDatabase(file:file).snapshot.records,expectedReload.records)
    }
    func testCachedCatalogPreservesEntireSnapshotAndInvalidatesChangedDraws()throws{
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer{try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
        var db=try LocalDatabase(file:file)
        try db.update{$0.draws=TestCatalog.five()}
        for status in ["SUBMIT_INTENT","SUBMITTED"]{
            try db.update{$0.records["draws"]=ParticipationRecord(id:"draws",product:"\"draws\":[] 🌀",store:"店家",status:status,evidence:"literal \"draws\":[] must stay text")}
            try assertFullSnapshot(db,file:file)
        }
        try db.update{$0.draws[0].product="新商品";$0.draws[0].archived=true;$0.draws[0].endsAt=Date(timeIntervalSince1970:1791000000.125);$0.draws.reverse()}
        try assertFullSnapshot(db,file:file)
        try db.update{$0.draws=[];$0.records.removeValue(forKey:"draws")}
        try assertFullSnapshot(db,file:file)
        try db.update{$0.draws=TestCatalog.five()}
        try assertFullSnapshot(db,file:file)
    }
    func testFailedWriteCannotCommitCachedCandidateCatalog()throws{
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file=folder.appendingPathComponent("state.json"),backup=folder.appendingPathComponent("backup.json")
        defer{try? FileManager.default.removeItem(at:folder)}
        var db=try LocalDatabase(file:file);try db.update{$0.draws=TestCatalog.five()}
        let original=db.snapshot.draws
        try FileManager.default.moveItem(at:file,to:backup)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        XCTAssertThrowsError(try db.update{$0.draws[0].product="must not commit"})
        XCTAssertEqual(db.snapshot.draws,original)
        try FileManager.default.removeItem(at:file);try FileManager.default.moveItem(at:backup,to:file)
        try db.update{$0.records["new"]=ParticipationRecord(id:"new",product:"測試",store:"店家",status:"SUBMIT_INTENT",evidence:"durable")}
        try assertFullSnapshot(db,file:file)
    }
    func testLargeCatalogFragmentReuseKeepsIntentAndSubmitDurable()throws{
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer{try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
        var db=try LocalDatabase(file:file)
        try db.update{snapshot in
            snapshot.draws=(0..<3100).map{i in var row=TestCatalog.demo()[0];row.id="catalog-\(i)";row.activityKey=row.id;return row}
            for i in 0..<1900{snapshot.records["record-\(i)"]=ParticipationRecord(id:"record-\(i)",product:"測試",store:"店家",status:"SUBMITTED",evidence:"fixture",updatedAt:Date(timeIntervalSince1970:1791000000+Double(i)))}
        }
        let began=ProcessInfo.processInfo.systemUptime
        _=try WireJSON.encoder(sortedKeys:false).encode(db.snapshot)
        let fullSeconds=ProcessInfo.processInfo.systemUptime-began
        for status in ["SUBMIT_INTENT","SUBMITTED"]{
            try db.update{$0.records["probe"]=ParticipationRecord(id:"probe",product:"測試",store:"店家",status:status,evidence:"durable")}
            XCTAssertEqual(try LocalDatabase(file:file).snapshot.records["probe"]?.status,status)
            try assertFullSnapshot(db,file:file)
        }
        print("Full snapshot encode: \(fullSeconds)s; cached catalog encode: \(db.lastWriteTiming.encodeSeconds)s")
    }
    func testSharedTimestampCachePreservesWireValuesAcrossDurableWrites()throws{
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer{try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
        var db=try LocalDatabase(file:file)
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let dates=(0..<9000).map{Date(timeIntervalSince1970:1790912000+Double($0)/1000)}
        for _ in 0..<2 {
            let values=try JSONDecoder().decode([String].self,from:WireJSON.encoder().encode(dates))
            XCTAssertEqual(values,dates.map{formatter.string(from:$0)})
        }
        for status in ["SUBMIT_INTENT","SUBMITTED"] {
            try db.update{$0.records["durable"]=ParticipationRecord(id:"durable",product:"測試",store:"店家",status:status,evidence:"durable",updatedAt:dates.last!)}
            let reloaded=try LocalDatabase(file:file)
            XCTAssertEqual(reloaded.snapshot.records["durable"]?.status,status)
            XCTAssertEqual(reloaded.snapshot.records["durable"]?.updatedAt.timeIntervalSince1970,dates.last!.timeIntervalSince1970)
        }
    }
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
