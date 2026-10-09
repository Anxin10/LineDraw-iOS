import XCTest
import CoreGraphics
@testable import LineDrawCore

// Added with the fast-path implementation. Execution is pending user approval.
final class DeviceElementLookupTests:XCTestCase {
    func testNotWonPunctuationVariantsReachTargetedClassifier() throws {
        let predicate = NSPredicate(format: DeviceElementLookup.predicate)
        for label in ["可惜..沒有抽中！", "可惜...沒有抽中！", "可惜…沒有抽中！", "可惜⋯沒有抽中！", "可惜沒有抽中！", "可惜．． 沒有抽中 !"] {
            XCTAssertTrue(predicate.evaluate(with: ["type":"XCUIElementTypeButton", "label":label, "name":label, "value":""]))
            XCTAssertTrue(DeviceScreenRules.isRelevant(label))
            var rows=payload(label:label);rows[2]["enabled"]=false
            let screen=try DeviceElementLookup.screen(from:rows,bundle:DeviceScreenRules.lineBundle)
            XCTAssertEqual(DeviceScreenRules.classify(screen), .terminal("COMPLETE"))
            XCTAssertTrue(DeviceScreenRules.acceptsOCR(label,confidence:0.5,hasCouponContext:true))
            XCTAssertFalse(DeviceScreenRules.acceptsOCR(label,confidence:0.5,hasCouponContext:false))
            var unrelated=screen;unrelated.nodes.remove(at:1)
            XCTAssertEqual(DeviceScreenRules.classify(unrelated), .wait)
        }
    }
    func testTargetedFailureDisablesFastQueryForTheRestOfSession(){
        var budget=DeviceLookupBudget();XCTAssertFalse(budget.preferFull)
        budget.recordFailure();XCTAssertTrue(budget.preferFull)
        budget.recordTargeted(0.01);budget.recordFull(2)
        XCTAssertTrue(budget.preferFull)
    }
    func row(_ type:String,_ label:String,rect:ScreenRect,enabled:Bool=true,displayed:Bool=true)->[String:Any] {
        ["type":type,"label":label,"attribute/name":label,"attribute/value":NSNull(),
         "rect":["x":rect.x,"y":rect.y,"width":rect.width,"height":rect.height],
         "enabled":enabled,"displayed":displayed]
    }
    func payload(width:Double=400,height:Double=800,label:String="加入好友並參加抽獎")->[[String:Any]] {
        [row("XCUIElementTypeApplication","LINE",rect:.init(x:0,y:0,width:width,height:height)),
         row("XCUIElementTypeStaticText","官方帳號優惠券",rect:.init(x:16,y:height*0.08,width:width-32,height:32)),
         row("XCUIElementTypeButton",label,rect:.init(x:0,y:height*0.82,width:width,height:height*0.1))]
    }
    func testDifferentPhoneSizesUseLiveButtonGeometry()throws {
        for (width,height) in [(320.0,568.0),(375.0,812.0),(393.0,852.0),(440.0,957.0),(957.0,440.0)] {
            let s=try DeviceElementLookup.screen(from:payload(width:width,height:height),bundle:DeviceScreenRules.lineBundle)
            XCTAssertEqual(s.width,width);XCTAssertEqual(s.height,height)
            guard case .click("ADD_FRIEND_AND_SUBMIT",let node)=DeviceScreenRules.classify(s) else{return XCTFail("Missing target for \(width)x\(height)")}
            XCTAssertEqual(node.rect.x+node.rect.width/2,width/2,accuracy:0.001)
            XCTAssertEqual(node.rect.y+node.rect.height/2,height*0.87,accuracy:0.001)
        }
    }
    func testIncompleteCompactOrInvalidGeometryResponsesRequireFallback() {
        XCTAssertThrowsError(try DeviceElementLookup.screen(from:[["ELEMENT":"cached-id"]],bundle:"jp.naver.line"))
        var missing=payload();missing[2].removeValue(forKey:"enabled")
        XCTAssertThrowsError(try DeviceElementLookup.screen(from:missing,bundle:"jp.naver.line"))
        var invalid=payload();invalid[0]["rect"]=["x":0.0,"y":0.0,"width":Double.nan,"height":800.0]
        XCTAssertThrowsError(try DeviceElementLookup.screen(from:invalid,bundle:"jp.naver.line"))
        XCTAssertThrowsError(try DeviceElementLookup.screen(from:Array(payload().dropFirst()),bundle:"jp.naver.line"))
        var duplicate=payload();duplicate.append(duplicate[0])
        XCTAssertThrowsError(try DeviceElementLookup.screen(from:duplicate,bundle:"jp.naver.line"))
    }
    func testHiddenAndDisabledButtonsNeverAuthorizeTaps()throws {
        for field in ["enabled","displayed"] {
            var rows=payload();rows[2][field]=false
            let s=try DeviceElementLookup.screen(from:rows,bundle:DeviceScreenRules.lineBundle)
            XCTAssertEqual(DeviceScreenRules.classify(s),.wait)
        }
    }
    func testNilOptionalAttributesMayBeOmittedByWDA()throws {
        var rows=payload()
        for index in rows.indices{rows[index].removeValue(forKey:"attribute/value");rows[index].removeValue(forKey:"attribute/name")}
        let s=try DeviceElementLookup.screen(from:rows,bundle:DeviceScreenRules.lineBundle)
        guard case .click("ADD_FRIEND_AND_SUBMIT",_)=DeviceScreenRules.classify(s) else{return XCTFail("Nil attributes should not disable lookup")}
    }
    func testEndedAndClaimedButtonsRemainTerminalWhenDisabled()throws {
        for (label,status) in [("已結束","ENDED"),("查看已領取的優惠券","ALREADY"),("使用優惠券","ALREADY"),("可惜...沒有抽中！","COMPLETE")] {
            var rows=payload(label:label);rows[2]["enabled"]=false
            let s=try DeviceElementLookup.screen(from:rows,bundle:DeviceScreenRules.lineBundle)
            XCTAssertEqual(DeviceScreenRules.classify(s),.terminal(status))
        }
    }
    func testAlertOrBlockerPreventsFastTargetTap()throws {
        for (type,label) in [("XCUIElementTypeAlert",""),("XCUIElementTypeStaticText","請輸入驗 證 碼")] {
            var rows=payload();rows.append(row(type,label,rect:.init(x:20,y:200,width:300,height:100)))
            let s=try DeviceElementLookup.screen(from:rows,bundle:DeviceScreenRules.lineBundle)
            guard case .pause=DeviceScreenRules.classify(s) else{return XCTFail("Ignored \(type)")}
        }
    }
    func testMultipleTargetsAreNotReducedToFirstMatch()throws {
        var rows=payload();rows.append(row("XCUIElementTypeButton","抽選",rect:.init(x:20,y:760,width:120,height:32)))
        let s=try DeviceElementLookup.screen(from:rows,bundle:DeviceScreenRules.lineBundle)
        guard case .pause=DeviceScreenRules.classify(s) else{return XCTFail("Ambiguous target")}
    }
    func testExpandedLayoutRequiresFullContextAndNativeButton()throws {
        var s=try DeviceElementLookup.screen(from:payload(label:"抽選"),bundle:DeviceScreenRules.lineBundle)
        s.nodes[2].rect.y=300
        XCTAssertEqual(DeviceScreenRules.classify(s),.wait)
        s.targeted=false
        guard case .click=DeviceScreenRules.classify(s) else{return XCTFail("Full coupon should support a relocated button")}
        s.nodes[2].ocr=true
        XCTAssertEqual(DeviceScreenRules.classify(s),.wait)
        s.nodes[2].ocr=false;s.nodes.remove(at:1)
        XCTAssertEqual(DeviceScreenRules.classify(s),.wait)
    }
    func testOutOfBoundsTargetIsNeverClicked()throws {
        var s=try DeviceElementLookup.screen(from:payload(),bundle:DeviceScreenRules.lineBundle)
        s.nodes[2].rect.x=399
        XCTAssertEqual(DeviceScreenRules.classify(s),.wait)
    }
    func testLookupStrategyAndUnrelatedTextCannotFakeNavigation()throws {
        let fast=try DeviceElementLookup.screen(from:payload(),bundle:DeviceScreenRules.lineBundle)
        var full=fast;full.targeted=false;full.nodes.reverse()
        full.nodes.append(.init(type:"XCUIElementTypeStaticText",labels:["商品載入中"],rect:.init(x:20,y:200,width:100,height:40)))
        XCTAssertEqual(full.navigationFingerprint,fast.navigationFingerprint)
        XCTAssertEqual(DeviceScreenRules.stabilityKey(full,decision:DeviceScreenRules.classify(full)),DeviceScreenRules.stabilityKey(fast,decision:DeviceScreenRules.classify(fast)))
        full.width=440
        XCTAssertNotEqual(full.navigationFingerprint,fast.navigationFingerprint)
        XCTAssertNotEqual(DeviceScreenRules.stabilityKey(full,decision:DeviceScreenRules.classify(full)),DeviceScreenRules.stabilityKey(fast,decision:DeviceScreenRules.classify(fast)))
    }
    func testBottomCropCoordinatesMapToLogicalScreenPoints() {
        for (width,height) in [(375.0,812.0),(440.0,957.0),(957.0,440.0)] {
            let rect=ScreenRect.fromVision(CGRect(x:0.25,y:0.25,width:0.5,height:0.25),region:DeviceElementLookup.bottomRegion,width:width,height:height)
            XCTAssertEqual(rect.x,width*0.25,accuracy:0.001)
            XCTAssertEqual(rect.y,height*0.8,accuracy:0.001)
            XCTAssertEqual(rect.height,height*0.1,accuracy:0.001)
            XCTAssertTrue(rect.isInside(width:width,height:height))
        }
    }
    func testPredicateIncludesBlockersResultsAndWhitespaceVariants() {
        let predicate=NSPredicate(format:DeviceElementLookup.predicate)
        for label in DeviceScreenRules.observationLabels+DeviceScreenRules.blockers+["請輸入驗　證　碼","ＣＡＰＴＣＨＡ","加入好友\n並參加抽獎"] {
            XCTAssertTrue(predicate.evaluate(with:["type":"XCUIElementTypeStaticText","label":label,"name":"","value":""]),label)
        }
        XCTAssertFalse(predicate.evaluate(with:["type":"XCUIElementTypeStaticText","label":"商品載入中","name":"","value":""]))
        XCTAssertFalse(predicate.evaluate(with:["type":"XCUIElementTypeButton","label":"voiceButton","name":"voiceButton","value":""]))
        XCTAssertTrue(predicate.evaluate(with:["type":"XCUIElementTypeAlert","label":"","name":"","value":""]))
    }
    func testLookupBudgetKeepsFasterPathAndRequiresMultipleSamples() {
        var slow=DeviceLookupBudget();slow.recordFull(0.3);slow.recordFull(0.4);slow.recordTargeted(1)
        XCTAssertFalse(slow.preferFull)
        slow.recordTargeted(0.8);XCTAssertTrue(slow.preferFull)
        var fast=DeviceLookupBudget();fast.recordFull(0.8);fast.recordFull(1);fast.recordTargeted(0.3);fast.recordTargeted(0.4)
        XCTAssertFalse(fast.preferFull)
        var jitter=DeviceLookupBudget();jitter.recordFull(0.4);jitter.recordFull(0.4);jitter.recordTargeted(0.42);jitter.recordTargeted(0.44)
        jitter.recordTargeted(.nan);jitter.recordFull(-1);XCTAssertFalse(jitter.preferFull)
    }
    func testObservedChineseOCRConfidenceRequiresCouponContextAndExactAction() {
        XCTAssertTrue(DeviceScreenRules.acceptsOCR("抽選",confidence:0.5,hasCouponContext:true))
        XCTAssertFalse(DeviceScreenRules.acceptsOCR("抽選",confidence:0.5,hasCouponContext:false))
        XCTAssertFalse(DeviceScreenRules.acceptsOCR("抽選",confidence:0.49,hasCouponContext:true))
        XCTAssertFalse(DeviceScreenRules.acceptsOCR("未知操作",confidence:0.5,hasCouponContext:true))
        XCTAssertFalse(DeviceScreenRules.acceptsOCR("抽選說明",confidence:0.5,hasCouponContext:true))
        var s=DeviceScreenTests().screen([])
        s.nodes.append(.init(type:"OCR",labels:["使用優惠券"],rect:.init(x:100,y:700,width:100,height:30),ocr:true))
        XCTAssertEqual(DeviceScreenRules.classify(s),.terminal("ALREADY"))
    }
}
