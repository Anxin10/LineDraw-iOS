import XCTest
@testable import LineDrawCore

final class DeviceScreenTests:XCTestCase {
    func screen(_ labels:[String],enabled:Bool=true)->DeviceScreen {
        DeviceScreen(bundle:DeviceScreenRules.lineBundle,width:400,height:800,nodes:[ScreenNode(type:"XCUIElementTypeStaticText",labels:["官方帳號優惠券"],rect:.init(x:10,y:60,width:250,height:30))]+labels.enumerated().map{i,label in ScreenNode(type:"XCUIElementTypeButton",labels:[label],rect:.init(x:10+Double(i)*190,y:700,width:180,height:60),enabled:enabled)})
    }
    func testTerminalPagesNeverBecomeTapTargets(){for label in ["查看已領取的優惠券","使用優惠券","恭喜中獎","未中獎","銘謝惠顧","可惜...沒有抽中！","已結束"]{guard case .terminal = DeviceScreenRules.classify(screen([label],enabled:false)) else{return XCTFail(label)}}}
    func testBottomOnlyAndCombinedFriend(){var s=screen(["加入好友並參加抽獎"]);guard case .click("ADD_FRIEND_AND_SUBMIT",_)=DeviceScreenRules.classify(s) else{return XCTFail()};guard case .pause=DeviceScreenRules.classify(s,autoFriend:false) else{return XCTFail()};s.nodes[1].rect.y=100;XCTAssertEqual(DeviceScreenRules.classify(s),.wait)}
    func testMultipleTargetsAndForeignAppPause(){guard case .pause=DeviceScreenRules.classify(screen(["抽選","參加抽選"])) else{return XCTFail()};var s=screen(["抽選"]);s.bundle="other";guard case .pause=DeviceScreenRules.classify(s) else{return XCTFail()}}
    func testAlertBlocksEvenKnownTerminal(){var s=screen(["已結束"]);s.nodes.append(.init(type:"XCUIElementTypeAlert",labels:[],rect:.init(x:20,y:200,width:100,height:100)));guard case .pause=DeviceScreenRules.classify(s) else{return XCTFail()}}
    func testXMLSecurityAndObservedWebWrapper()throws{
        XCTAssertThrowsError(try DeviceScreenRules.parse("<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///secret'>]><a>&x;</a>"))
        let xml="""
        <XCUIElementTypeApplication><XCUIElementTypeWebView visible="true" x="0" y="0" width="400" height="800"><XCUIElementTypeOther visible="false" accessible="false" x="0" y="0" width="400" height="800"><XCUIElementTypeButton visible="true" label="抽選" x="0" y="700" width="400" height="100"/></XCUIElementTypeOther></XCUIElementTypeWebView></XCUIElementTypeApplication>
        """
        XCTAssertTrue(try DeviceScreenRules.parse(xml).contains{$0.labels.contains("抽選")})
        XCTAssertThrowsError(try DeviceScreenRules.parse("<broken>"))
    }
}

@MainActor final class DeviceBatchTests:XCTestCase {
    func testSuccessfulObservationsAdvanceWhileFirstPageIsLoading(){
        var work=DeviceWorkProgress(),p=DeviceBatchProgress();p.total=5;p.itemStep=1;work.update(p)
        let before=work.completed
        work.observed();XCTAssertEqual(work.completed,before+1)
        work.update(p);XCTAssertEqual(work.completed,before+1) // repeated UI publish is not new work
        for _ in 0..<100{work.observed()}
        XCTAssertGreaterThan(work.total,work.completed)
        p.index=5;p.itemStep=0;work.update(p)
        XCTAssertGreaterThan(work.total,work.completed) // shutdown is still pending
        p.total=8;let completed=work.completed;work.update(p)
        XCTAssertEqual(work.completed,completed);XCTAssertGreaterThan(work.total,work.completed)
    }
    final class Driver:DeviceDriver {
        var snapshots=[DeviceScreen]();var opens=[String]();var taps=0;var network=true;var tapError:Error?;var onTap:(()->Void)?;var current=0;var sequence=[DeviceScreen]();var baseline="navigation-boundary"
        var onSnapshot:(()->Void)?
        var useDirectNavigation=false;var navigation:DeviceNavigationGuard?;var now:()->TimeInterval={0};var events=[String]()
        func open(_ url:String)async throws->String{
            events.append("open");opens.append(url);current=min(opens.count-1,max(snapshots.count-1,0))
            if useDirectNavigation{navigation=DeviceNavigationGuard(expectedBundle:DeviceScreenRules.lineBundle,targetURL:url);navigation?.didOpen(at:now())}
            return baseline
        }
        func snapshot()async throws->DeviceScreen{
            events.append("read");onSnapshot?()
            var screen = !sequence.isEmpty ? sequence.removeFirst():snapshots[min(current,snapshots.count-1)]
            if var navigation{let ready=navigation.observe(screen,at:now());self.navigation=navigation;screen.navigationVerified=ready;screen.navigationPending = !ready}
            return screen
        }
        func tap(_ target:ScreenNode)async throws{events.append("tap");taps+=1;onTap?();if let tapError{throw tapError}}
        func online()async->Bool{network}
    }
    var records=[String:ParticipationRecord]();var time:Double=0
    func row(_ index:Int)->Draw{var r=TestCatalog.five()[index];r.startsAt=Date().addingTimeInterval(-3600);r.endsAt=Date().addingTimeInterval(3600);return r}
    func engine(_ d:Driver,fetch:(()async throws->[Draw])?=nil,write:((Draw,ParticipationRecord?)throws->Void)?=nil)->DeviceBatch{
        DeviceBatch(driver:d,read:{self.records[$0]},write:write ?? {self.records[$0.activityKey]=$1},update:{_ in},fetch:fetch,clock:{self.time},sleep:{self.time+=$0;await Task.yield()})
    }
    func testOldCouponWhileNewPageLoadsCannotBeMarkedComplete()async{
        let d=Driver(),old=DeviceScreenTests().screen(["恭喜中獎"]),ready=DeviceScreenTests().screen(["抽選"])
        d.baseline=old.navigationFingerprint;d.sequence=[old,old,DeviceScreenTests().screen([]),ready];d.snapshots=[ready]
        let e=engine(d);await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,1);XCTAssertEqual(records[row(0).activityKey]?.status,"SUBMITTED")
    }
    func testTransientDrawButtonDuringNavigationIsNotClicked()async{
        let d=Driver();d.sequence=[DeviceScreenTests().screen(["抽選"])];d.snapshots=[DeviceScreenTests().screen(["已結束"])]
        let e=engine(d);await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,0);XCTAssertEqual(records[row(0).activityKey]?.status,"ENDED")
    }
    func testForegroundInterruptionResetsTargetStability()async {
        let d=Driver(),ready=DeviceScreenTests().screen(["抽選"])
        var system=ready;system.bundle="com.apple.springboard"
        d.sequence=[ready,system,ready];d.snapshots=[DeviceScreenTests().screen(["已結束"])]
        let e=engine(d)
        await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,0);XCTAssertEqual(records[row(0).activityKey]?.status,"ENDED")
    }
    func testUnrelatedTextDoesNotDelayStableTarget()async {
        let d=Driver(),ready=DeviceScreenTests().screen(["抽選"])
        var changed=ready
        changed.nodes.append(.init(type:"XCUIElementTypeStaticText",labels:["商品介紹更新"],rect:.init(x:20,y:200,width:200,height:40)))
        d.sequence=[ready,changed];d.snapshots=[DeviceScreenTests().screen(["已結束"])]
        let e=engine(d)
        await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,1);XCTAssertEqual(records[row(0).activityKey]?.status,"SUBMITTED")
    }
    func testDispatchAckAdvancesWithoutWaitingForResults()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen(["抽選"])];let e=engine(d)
        await e.run([row(0),row(1)],allInitial:[row(0),row(1)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,2);XCTAssertEqual(e.progress.state,"COMPLETED");XCTAssertEqual(records.values.map(\.status),["SUBMITTED","SUBMITTED"])
    }
    func testDirectNavigationWithProgressOverCloseRunsDrawWinLossAndEndedInOrder()async {
        let d=Driver();d.useDirectNavigation=true;d.now={self.time}
        d.snapshots=["抽選","加入好友並參加抽獎","查看已領取的優惠券","可惜...沒有抽中！","已結束"].map{label in
            var screen=DeviceScreenTests().screen([label])
            screen.nodes.append(.init(type:"XCUIElementTypeStaticText",labels:["LineDraw 抽選"],rect:.init(x:20,y:30,width:350,height:90)))
            screen.nodes.append(.init(type:"XCUIElementTypeButton",labels:["關閉"],rect:.init(x:350,y:70,width:40,height:40)))
            return screen
        }
        let rows=(0..<5).map(row),e=engine(d)
        await e.run(rows,allInitial:rows,filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(e.progress.state,"COMPLETED");XCTAssertEqual(d.opens,rows.map{$0.canonicalURL!})
        XCTAssertEqual(d.taps,2)
        XCTAssertEqual(rows.map{records[$0.activityKey]?.status},["SUBMITTED","SUBMITTED","ALREADY","COMPLETE","ENDED"])
    }
    func testNextURLImmediatelyFollowsAcknowledgedTapAndDurableSave()async {
        let d=Driver();d.useDirectNavigation=true;d.now={self.time};d.snapshots=[DeviceScreenTests().screen(["抽選"])]
        let e=engine(d,write:{row,record in self.records[row.activityKey]=record;d.events.append("save:"+(record?.status ?? "nil"))})
        await e.run([row(0),row(1)],allInitial:[row(0),row(1)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        guard let index=d.events.firstIndex(of:"tap") else{return XCTFail("No tap")}
        XCTAssertEqual(Array(d.events[index...].prefix(3)),["tap","save:SUBMITTED","open"])
        XCTAssertEqual(d.taps,2);XCTAssertEqual(e.progress.state,"COMPLETED")
    }
    func testVerifiedNativeButtonUsesOneObservationPerItem()async {
        let d=Driver();var ready=DeviceScreenTests().screen(["抽選"]);ready.navigationVerified=true
        d.snapshots=[ready];var reads=0;d.onSnapshot={reads+=1}
        let e=engine(d);await e.run([row(0),row(1)],allInitial:[row(0),row(1)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,2);XCTAssertEqual(reads,2);XCTAssertEqual(time,0)
        XCTAssertEqual(e.itemTimings.map(\.reads),[1,1]);XCTAssertEqual(e.itemTimings.map(\.status),["SUBMITTED","SUBMITTED"])
    }
    func testPendingOldResultNeverCompletesNextItem()async {
        let d=Driver();var old=DeviceScreenTests().screen(["恭喜中獎"]);old.navigationPending=true
        var ready=DeviceScreenTests().screen(["抽選"]);ready.navigationVerified=true
        d.sequence=[old,old];d.snapshots=[ready]
        let e=engine(d);await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,1);XCTAssertEqual(records[row(0).activityKey]?.status,"SUBMITTED")
    }
    func testOCRDoesNotUseNativeSingleObservationShortcut()async {
        let d=Driver();var ready=DeviceScreenTests().screen(["抽選"]);ready.navigationVerified=true;ready.nodes[1].ocr=true;ready.nodes[1].type="OCR"
        d.sequence=[ready];d.snapshots=[DeviceScreenTests().screen(["已結束"])]
        let e=engine(d);await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,0);XCTAssertEqual(records[row(0).activityKey]?.status,"ENDED")
    }
    func testSingleObservationCannotBypassExpiredLoadWindow()async {
        let d=Driver();var ready=DeviceScreenTests().screen(["抽選"]);ready.navigationVerified=true;d.snapshots=[ready]
        d.onSnapshot={self.time+=31}
        let e=engine(d);await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,0);XCTAssertEqual(records[row(0).activityKey]?.status,"LOAD_TIMEOUT")
    }
    func testActualMilestonesAdvanceMonotonicallyAndReserveCleanup()async {
        let d=Driver();var ready=DeviceScreenTests().screen(["抽選"]);ready.navigationVerified=true;d.snapshots=[ready]
        var observed=[Int64]();var total:Int64=0
        let e=DeviceBatch(driver:d,read:{self.records[$0]},write:{self.records[$0.activityKey]=$1},update:{observed.append($0.workCompleted);total=$0.workTotal},clock:{self.time},sleep:{self.time+=$0})
        d.onSnapshot={XCTAssertTrue(observed.contains(1))}
        d.onTap={XCTAssertTrue(observed.contains(3))}
        await e.run([row(0),row(1)],allInitial:[row(0),row(1)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(observed,observed.sorted());XCTAssertEqual(observed.last,12);XCTAssertEqual(total,13)
        XCTAssertTrue(observed.contains(4));XCTAssertTrue(observed.contains(5))
    }
    func testTerminalLayoutMotionDoesNotRequireMoreThanTwoReads()async {
        let d=Driver();var a=DeviceScreenTests().screen(["查看已領取的優惠券"]);a.navigationVerified=true
        var b=a;b.nodes[1].rect.y=650
        d.sequence=[a,b];d.snapshots=[DeviceScreenTests().screen([])]
        let e=engine(d);await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,0);XCTAssertEqual(records[row(0).activityKey]?.status,"ALREADY")
        XCTAssertEqual(e.itemTimings.first?.reads,2)
    }
    func testKnownResultsAndEndedSkipWithoutTap()async{
        let d=Driver();d.snapshots=["恭喜中獎","可惜...沒有抽中！","已結束","查看已領取的優惠券"].map{DeviceScreenTests().screen([$0])};let e=engine(d);let rows=(0..<4).map(row)
        await e.run(rows,allInitial:rows,filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,0);XCTAssertEqual(e.progress.index,4);XCTAssertEqual(records[row(2).activityKey]?.status,"ENDED")
    }
    func testEndedPeriodBodyAndDialogContinueToNextDrawWithoutAnyDismissTap()async{
        let d=Driver();d.useDirectNavigation=true;d.now={self.time}
        d.snapshots=[EndedNoticeTests.notice(),EndedNoticeTests.notice(alert:true),DeviceScreenTests().screen(["抽選"])]
        let rows=(0..<3).map(row),e=engine(d)
        await e.run(rows,allInitial:rows,filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(e.progress.state,"COMPLETED");XCTAssertEqual(e.progress.index,3)
        XCTAssertEqual(d.opens,rows.map{$0.canonicalURL!});XCTAssertEqual(d.taps,1)
        XCTAssertEqual(rows.map{records[$0.activityKey]?.status},["ENDED","ENDED","SUBMITTED"])
    }
    func testUnknownTapFailureIsReviewAndNeverRetries()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen(["抽選"])];d.tapError=DeviceDriverError.disconnected;let e=engine(d)
        await e.run([row(0),row(1)],allInitial:[row(0),row(1)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,1);XCTAssertEqual(d.opens.count,1);XCTAssertEqual(records[row(0).activityKey]?.status,"REVIEW");XCTAssertEqual(e.progress.state,"STOPPED")
    }
    func testDiskFailurePreventsTap()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen(["抽選"])];let e=engine(d,write:{_,_ in throw LineDrawError.message("disk full")})
        await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false);XCTAssertEqual(d.taps,0)
    }
    func testIntentIsPersistedBeforeDispatchAndStopSkipsNext()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen(["抽選"])];let e=engine(d)
        d.onTap={XCTAssertEqual(self.records[self.row(0).activityKey]?.status,"SUBMIT_INTENT");e.stop()}
        await e.run([row(0),row(1)],allInitial:[row(0),row(1)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.taps,1);XCTAssertEqual(records[row(0).activityKey]?.status,"SUBMITTED");XCTAssertEqual(e.progress.state,"STOPPED")
    }
    func testSlowLoadingReopensOnceAndMovesOn()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen([])];let e=engine(d)
        await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.opens.count,2);XCTAssertEqual(d.taps,0);XCTAssertEqual(records[row(0).activityKey]?.status,"LOAD_TIMEOUT")
    }
    func testNetworkWaitBoundedAndDoesNotOpenCoupon()async{
        let d=Driver();d.network=false;let e=engine(d)
        await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.opens.count,0);XCTAssertGreaterThanOrEqual(time,60);XCTAssertLessThan(time,62)
    }
    func testLateSecondSnapshotCannotAuthorizeTapBeyondLoadWindow()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen(["抽選"])];var reads=0
        d.onSnapshot={reads+=1;if reads.isMultiple(of:2){self.time+=31}}
        let e=engine(d)
        await e.run([row(0)],allInitial:[row(0)],filter:CatalogFilter(),autoFriend:true,autoContinue:false)
        XCTAssertEqual(d.opens.count,2);XCTAssertEqual(d.taps,0)
        XCTAssertEqual(records[row(0).activityKey]?.status,"LOAD_TIMEOUT")
    }
    func testAppendOnlyUnseenSelectedFilterAndNeverUnselectedOriginal()async{
        let d=Driver();d.snapshots=[DeviceScreenTests().screen(["抽選"])];let a=row(0),unselected=row(1),new=row(2);var calls=0
        let e=engine(d,fetch:{calls+=1;return [a,unselected,new]})
        await e.run([a],allInitial:[a,unselected],filter:CatalogFilter(),autoFriend:true,autoContinue:true)
        XCTAssertEqual(d.opens,[a.canonicalURL!,new.canonicalURL!]);XCTAssertEqual(calls,2);XCTAssertNil(records[unselected.activityKey]);XCTAssertEqual(e.progress.total,2)
    }
    func testReviewRecordBlocksRestart()async{
        let d=Driver();let a=row(0);records[a.activityKey]=ParticipationRecord(id:a.activityKey,product:a.product,store:a.store,status:"REVIEW",evidence:"unknown");let e=engine(d)
        await e.run([a],allInitial:[a],filter:CatalogFilter(),autoFriend:true,autoContinue:false);XCTAssertTrue(d.opens.isEmpty)
    }
}
