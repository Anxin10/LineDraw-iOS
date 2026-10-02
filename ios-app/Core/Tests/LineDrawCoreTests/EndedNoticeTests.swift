import XCTest
@testable import LineDrawCore

final class EndedNoticeTests:XCTestCase{
    static func notice(_ text:String="抽獎期間已結束",alert:Bool=false)->DeviceScreen{
        let label=ScreenNode(type:"XCUIElementTypeStaticText",labels:[text],rect:.init(x:40,y:320,width:320,height:40),enabled:false)
        var nodes=[label]
        if alert{nodes.append(.init(type:"XCUIElementTypeAlert",labels:["提醒"],rect:.init(x:20,y:260,width:360,height:220)))}
        return DeviceScreen(bundle:DeviceScreenRules.lineBundle,width:400,height:800,nodes:nodes)
    }
    func testBodyDisabledButtonAndKnownDialogAreEnded(){
        for label in ["抽獎期間已結束","抽獎期間\n已結束！","抽選期間已結束。","抽籤期間已結束"]{
            XCTAssertEqual(DeviceScreenRules.classify(Self.notice(label)),.terminal("ENDED"))
            XCTAssertEqual(DeviceScreenRules.classify(Self.notice(label,alert:true)),.terminal("ENDED"))
            var footer=Self.notice(label);footer.nodes[0].rect.y=700;footer.nodes[0].type="XCUIElementTypeButton"
            XCTAssertEqual(DeviceScreenRules.classify(footer),.terminal("ENDED"))
        }
    }
    func testConditionsForeignAppAndUnrelatedDialogsDoNotSkip(){
        XCTAssertEqual(DeviceScreenRules.classify(Self.notice("如果抽獎期間已結束，請參加下次活動")),.wait)
        var foreign=Self.notice();foreign.bundle="com.apple.springboard"
        guard case .pause=DeviceScreenRules.classify(foreign) else{return XCTFail()}
        var unrelated=Self.notice(alert:true);unrelated.nodes[0].rect.y=700
        guard case .pause=DeviceScreenRules.classify(unrelated) else{return XCTFail()}
        var auth=Self.notice(alert:true);auth.nodes.append(.init(type:"XCUIElementTypeTextField",labels:["請輸入驗證碼"],rect:.init(x:40,y:380,width:300,height:40)))
        guard case .pause=DeviceScreenRules.classify(auth) else{return XCTFail()}
    }
    func testCouponInstructionsDoNotTurnEndedIntoLoginPrompt(){
        var s=Self.notice();s.nodes.append(.init(type:"XCUIElementTypeStaticText",labels:["使用優惠券時可能付款，本活動不需登入"],rect:.init(x:20,y:100,width:350,height:80)))
        XCTAssertEqual(DeviceScreenRules.classify(s),.terminal("ENDED"))
        s.nodes.append(.init(type:"XCUIElementTypeSecureTextField",labels:[],rect:.init(x:20,y:200,width:300,height:30)))
        XCTAssertNotEqual(DeviceScreenRules.classify(s),.terminal("ENDED"))
    }
    func testTargetedLookupAndBottomOCRKeepNotice()throws{
        let helper=DeviceElementLookupTests()
        for label in DeviceScreenRules.endedNotices{
            XCTAssertTrue(DeviceScreenRules.isRelevant(label))
            let predicate=NSPredicate(format:DeviceElementLookup.predicate)
            XCTAssertTrue(predicate.evaluate(with:["type":"XCUIElementTypeStaticText","label":label,"name":"","value":""]))
            let s=try DeviceElementLookup.screen(from:helper.payload(label:label),bundle:DeviceScreenRules.lineBundle)
            XCTAssertEqual(DeviceScreenRules.classify(s),.terminal("ENDED"))
            XCTAssertTrue(DeviceScreenRules.acceptsOCR(label,confidence:0.5,hasCouponContext:true))
            XCTAssertFalse(DeviceScreenRules.acceptsOCR(label,confidence:0.5,hasCouponContext:false))
            var ocr=Self.notice(label);ocr.nodes[0].ocr=true;ocr.nodes[0].rect.y=700
            XCTAssertEqual(DeviceScreenRules.classify(ocr),.terminal("ENDED"))
            ocr.nodes[0].rect.y=320;XCTAssertEqual(DeviceScreenRules.classify(ocr),.wait)
        }
    }
    func testEndedDialogPassesNormalNavigationChecksWithoutDismissing(){
        let s=Self.notice(alert:true),url=TestCatalog.five()[0].canonicalURL!
        var guardState=DeviceNavigationGuard(expectedBundle:s.bundle,targetURL:url)
        XCTAssertFalse(guardState.observe(s,at:1));guardState.didOpen(at:1)
        XCTAssertFalse(guardState.observe(s,at:1.1));XCTAssertTrue(guardState.observe(s,at:1.7))
        var wrong=s;wrong.nodes.append(.init(type:"XCUIElementTypeWebView",labels:[TestCatalog.five()[1].canonicalURL!],rect:.init(x:0,y:0,width:400,height:800)))
        var other=DeviceNavigationGuard(expectedBundle:s.bundle,targetURL:url);other.didOpen(at:1)
        XCTAssertFalse(other.observe(wrong,at:2));XCTAssertFalse(other.observe(wrong,at:3))
    }
}
