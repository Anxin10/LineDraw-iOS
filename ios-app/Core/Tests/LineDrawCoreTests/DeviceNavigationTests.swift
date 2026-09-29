import XCTest
@testable import LineDrawCore

@MainActor final class DeviceNavigationTests:XCTestCase {
    func testTransientNotificationWaitsForHeaderWithoutAnyGesture()async throws {
        var now=0.0,reads=0
        let observation=try await DeviceNavigation.awaitHeaderExposure(read:{reads+=1;return (nil,reads==3)},canAct:{true},clock:{now},sleep:{now+=$0})
        XCTAssertTrue(observation.headerVisible);XCTAssertEqual(reads,3);XCTAssertEqual(now,0.7,accuracy:0.01)
    }
    func testCoveredHeaderStopsAfterBoundedWait()async {
        var now=0.0
        do{_ = try await DeviceNavigation.awaitHeaderExposure(read:{(nil,false)},canAct:{true},clock:{now},sleep:{now+=$0});XCTFail("Expected stop")}
        catch{}
        XCTAssertGreaterThanOrEqual(now,6);XCTAssertLessThan(now,6.4)
    }
    func testHeaderWaitCannotAuthorizeAfterCancellationOrLateRead()async {
        var now=0.0,reads=0
        do{_ = try await DeviceNavigation.awaitHeaderExposure(read:{reads+=1;return (nil,true)},canAct:{false});XCTFail("Expected cancellation")}
        catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(reads,0)
        do{_ = try await DeviceNavigation.awaitHeaderExposure(read:{now=7;return (nil,true)},canAct:{true},clock:{now},sleep:{now+=$0});XCTFail("Late read cannot authorize")}
        catch{}
    }
    func testDirectNavigationNeverUsesOldDrawOrItsResultAsBoundary(){
        var guardState=DeviceNavigationGuard(expectedBundle:DeviceScreenRules.lineBundle,targetURL:TestCatalog.five()[1].canonicalURL!)
        for label in ["抽選","恭喜中獎","查看已領取的優惠券","已結束"]{
            XCTAssertFalse(guardState.observe(DeviceScreenTests().screen([label])))
        }
        XCTAssertFalse(guardState.verified)
    }
    func testNavigationNeedsFullDismissalOrExactDocumentIdentity(){
        let bundle=DeviceScreenRules.lineBundle,url=TestCatalog.five()[0].canonicalURL!
        var guardState=DeviceNavigationGuard(expectedBundle:bundle,targetURL:url)
        let app=ScreenNode(type:"XCUIElementTypeApplication",labels:["LINE"],rect:.init(x:0,y:0,width:400,height:800))
        var screen=DeviceScreen(bundle:bundle,width:400,height:800,nodes:[app],targeted:true)
        XCTAssertFalse(guardState.observe(screen))
        screen.targeted=false;screen.nodes.append(.init(type:"XCUIElementTypeWebView",labels:[],rect:app.rect))
        XCTAssertFalse(guardState.observe(screen))
        screen.nodes[1].labels=[TestCatalog.five()[1].canonicalURL!]
        XCTAssertFalse(guardState.observe(screen))
        screen.nodes[1].labels=[url];XCTAssertTrue(guardState.observe(screen))
        var second=DeviceNavigationGuard(expectedBundle:bundle,targetURL:url)
        screen.nodes=[app];XCTAssertTrue(second.observe(screen))
        XCTAssertTrue(second.observe(DeviceScreenTests().screen(["抽選"])))
        var next=DeviceNavigationGuard(expectedBundle:bundle,targetURL:TestCatalog.five()[1].canonicalURL!)
        XCTAssertFalse(next.observe(DeviceScreenTests().screen(["抽選"])))
    }
    func testEmptySourceForeignAppAndAlertCannotVerifyNavigation(){
        var guardState=DeviceNavigationGuard(expectedBundle:DeviceScreenRules.lineBundle,targetURL:TestCatalog.five()[0].canonicalURL!)
        var screen=DeviceScreen(bundle:DeviceScreenRules.lineBundle,width:400,height:800,nodes:[])
        XCTAssertFalse(guardState.observe(screen))
        screen.nodes=[.init(type:"XCUIElementTypeApplication",labels:[],rect:.init(x:0,y:0,width:400,height:800))]
        screen.bundle="com.apple.springboard";XCTAssertFalse(guardState.observe(screen))
        screen.bundle=DeviceScreenRules.lineBundle;screen.nodes.append(.init(type:"XCUIElementTypeAlert",labels:[],rect:.init(x:0,y:0,width:10,height:10)))
        XCTAssertFalse(guardState.observe(screen))
    }
    func testNativeFriendPageIsOutsideCouponButCombinedDrawIsNot(){
        let bundle=DeviceScreenRules.lineBundle
        var guardState=DeviceNavigationGuard(expectedBundle:bundle,targetURL:TestCatalog.five()[0].canonicalURL!)
        let app=ScreenNode(type:"XCUIElementTypeApplication",labels:["LINE"],rect:.init(x:0,y:0,width:400,height:800))
        var screen=DeviceScreen(bundle:bundle,width:400,height:800,nodes:[app,.init(type:"XCUIElementTypeButton",labels:["加入好友並參加抽獎"],rect:.init(x:0,y:700,width:400,height:60))])
        XCTAssertFalse(guardState.observe(screen))
        screen.nodes[1].labels=["加入好友"];XCTAssertTrue(guardState.observe(screen))
    }
    func testStackedOwnProgressTitlesUseFirstSafeTitleInsteadOfFailing(){
        let first=ScreenRect(x:100,y:55,width:100,height:20),second=ScreenRect(x:100,y:115,width:100,height:20)
        XCTAssertEqual(DeviceNavigation.progressBanner([second,first],width:440,height:956),first)
        XCTAssertNil(DeviceNavigation.progressBanner([],width:440,height:956))
        XCTAssertNil(DeviceNavigation.progressBanner([.init(x:100,y:800,width:100,height:20)],width:440,height:956))
        XCTAssertNil(DeviceNavigation.progressBanner([.init(x:420,y:55,width:100,height:20)],width:440,height:956))
    }
    func testObservedProgressTitleMapsFromCroppedVisionRegionToTopOfScreen(){
        let observed=CGRect(x:0.2318181824,y:0.5945945951,width:0.2590909091,height:0.1003861004)
        let rect=ScreenRect.fromVision(observed,region:CGRect(x:0,y:0.82,width:1,height:0.18),width:440,height:957)
        XCTAssertEqual(rect.x+rect.width/2,159,accuracy:0.01)
        XCTAssertEqual(rect.y+rect.height/2,61.189,accuracy:0.01)
        XCTAssertLessThan(rect.y+rect.height,80) // The real title is above LINE's y=84 Close button.
    }
    func testClosingAnimationMustDisappearForTwoFreshObservations()async throws {
        var pending=[true,true,false,true,false,false];var now=0.0;var reads=0
        try await DeviceNavigation.afterClosing(stillVisible:{reads+=1;return pending.removeFirst()},canAct:{true},clock:{now},sleep:{now+=$0})
        XCTAssertEqual(reads,6)
    }
    func testMissingCloseButtonDuringAnimationDoesNotMeanCouponClosed()async {
        var now=0.0
        do{try await DeviceNavigation.afterClosing(stillVisible:{true},canAct:{true},clock:{now},sleep:{now+=$0});XCTFail("Expected bounded stop")}catch{}
        XCTAssertGreaterThanOrEqual(now,6);XCTAssertLessThan(now,6.2)
    }
    func testCancelledCloseWaitNeverAuthorizesNextNavigation()async {
        var reads=0
        do{try await DeviceNavigation.afterClosing(stillVisible:{reads+=1;return true},canAct:{false});XCTFail("Expected cancellation")}
        catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(reads,0)
    }
}
