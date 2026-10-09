import XCTest
@testable import LineDrawCore

@MainActor final class MissedDrawScannerTests:XCTestCase {
    func testDeduplicatingBeforePaginationKeepsBatchCursorStable(){
        let original=(0..<65).map{i->Draw in var d=row(i%5);d.activityKey="page-\(i)";d.id="row-\(i)";return d}
        var aliases=original;aliases.insert(original[29],at:30);aliases.insert(original[59],at:61)
        let candidates=MissedDrawScanner.candidates(aliases)
        XCTAssertEqual(candidates.map(\.activityKey),original.map(\.activityKey))
        let batches=stride(from:0,to:candidates.count,by:30).flatMap{Array(candidates.dropFirst($0).prefix(30))}
        XCTAssertEqual(batches.map(\.activityKey),original.map(\.activityKey))
    }
    final class Driver:DeviceDriver {
        var screens=[DeviceScreen](),taps=0,opens=0,time=0.0
        var fail=false
        func open(_ url:String)async throws->String{opens+=1;time+=0.3;return "old-page"}
        func snapshot()async throws->DeviceScreen{time+=0.7;if fail{throw ObservationFailure.deadlineExceeded};return screens.removeFirst()}
        func tap(_ target:ScreenNode)async throws{taps+=1}
        func online()async->Bool{true}
    }
    func screen(_ label:String,pending:Bool=false)->DeviceScreen{
        DeviceScreen(bundle:DeviceScreenRules.lineBundle,width:400,height:800,nodes:[ScreenNode(type:"XCUIElementTypeButton",labels:[label],rect:ScreenRect(x:0,y:720,width:400,height:80))],targeted:true,navigationVerified:!pending,navigationPending:pending)
    }
    func row(_ index:Int)->Draw{var row=TestCatalog.five()[index];row.startsAt=Date().addingTimeInterval(-3600);row.endsAt=Date().addingTimeInterval(3600);return row}
    func testReadOnlyScanReportsMissedTerminalAndTimingsAndDeduplicates()async throws{
        let driver=Driver();driver.screens=[screen("參加抽獎"),screen("已結束")]
        var findings=[MissedDrawFinding]()
        let scanner=MissedDrawScanner(driver:driver,clock:{driver.time},sleep:{driver.time+=$0},update:{_,_,finding in if let finding{findings.append(finding)}})
        try await scanner.run([row(0),row(0),row(1)])
        XCTAssertEqual(findings.map(\.status),["MISSED","ENDED"])
        XCTAssertEqual(driver.opens,2);XCTAssertEqual(driver.taps,0)
        XCTAssertEqual(findings[0].openSeconds,0.3,accuracy:0.0001)
        XCTAssertEqual(findings[0].querySeconds,0.7,accuracy:0.0001)
        XCTAssertEqual(findings[0].totalSeconds,1,accuracy:0.0001)
    }
    func testPreviousCouponDuringNavigationDoesNotReportFalseMissed()async throws{
        let driver=Driver();driver.screens=[screen("參加抽獎",pending:true),screen("已結束")]
        var findings=[MissedDrawFinding]()
        let scanner=MissedDrawScanner(driver:driver,clock:{driver.time},sleep:{driver.time+=$0},update:{_,_,finding in if let finding{findings.append(finding)}})
        try await scanner.run([row(0)])
        XCTAssertEqual(findings.first?.status,"ENDED");XCTAssertEqual(findings.first?.reads,2);XCTAssertEqual(driver.taps,0)
    }
    func testTimeoutIsUnknownAndIncludesFailedReadTime()async throws{
        let driver=Driver();driver.fail=true
        var findings=[MissedDrawFinding]()
        let scanner=MissedDrawScanner(driver:driver,clock:{driver.time},sleep:{driver.time+=$0},update:{_,_,finding in if let finding{findings.append(finding)}})
        try await scanner.run([row(0)])
        XCTAssertEqual(findings.first?.status,"UNKNOWN");XCTAssertEqual(findings.first?.reads,1)
        XCTAssertEqual(findings.first!.querySeconds,0.7,accuracy:0.0001);XCTAssertEqual(driver.taps,0)
    }
    func testIdentityRequiresBothExpectedSKUAndStoreAndRejectsAnotherDocument(){
        var draw=row(0);draw.product="CX-01 測試商品";draw.store="Funbox 台中中友店"
        var s=screen("參加抽獎")
        func text(_ value:String)->ScreenNode{ScreenNode(type:"XCUIElementTypeStaticText",labels:[value],rect:ScreenRect(x:0,y:100,width:400,height:40))}
        s.nodes += [text("10/9 CX-01 測試商品"),text("Funbox-台中中友店")]
        XCTAssertTrue(ScanPageIdentity.matches(s,draw:draw))
        var other=s;other.nodes[1]=text("CX-010 其他商品")
        XCTAssertFalse(ScanPageIdentity.matches(other,draw:draw))
        other=s;other.nodes[2]=text("Funbox 新竹巨城店")
        XCTAssertFalse(ScanPageIdentity.matches(other,draw:draw))
        other=s;other.nodes.append(ScreenNode(type:"XCUIElementTypeWebView",labels:[row(1).canonicalURL!],rect:ScreenRect(x:0,y:0,width:400,height:800)))
        XCTAssertFalse(ScanPageIdentity.matches(other,draw:draw))
    }
    func testForeignForegroundStopsEmptyPollingAndStaysUnknown()async throws {
        let driver=Driver();var foreign=screen("參加抽獎");foreign.bundle="com.apple.springboard"
        driver.screens=Array(repeating:foreign,count:3)
        var findings=[MissedDrawFinding]()
        let scanner=MissedDrawScanner(driver:driver,clock:{driver.time},sleep:{driver.time+=$0},update:{_,_,finding in if let finding{findings.append(finding)}})
        try await scanner.run([row(0)])
        XCTAssertEqual(findings.first?.status,"UNKNOWN");XCTAssertNotNil(findings.first?.reason)
        XCTAssertLessThan(driver.time,4);XCTAssertEqual(driver.taps,0)
    }
}
