import XCTest
@testable import LineDrawCore

final class DiagnosticBatchTests:XCTestCase {
    func testLongTimingBatchPreservesFailureAndReloads()throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:file)}
        var db=try LocalDatabase(file:file)
        try db.log("DEVICE_BATCH_FINISHED","STOPPED: connection lost")
        try db.logMany((1...500).map{Diagnostic(code:"DEVICE_ITEM_TIMING",message:String($0))})
        let loaded=try LocalDatabase(file:file)
        XCTAssertEqual(loaded.snapshot.diagnostics.count,21)
        XCTAssertEqual(loaded.snapshot.diagnostics.first?.code,"DEVICE_BATCH_FINISHED")
        XCTAssertEqual(loaded.snapshot.diagnostics.last?.message,"500")
    }
}
