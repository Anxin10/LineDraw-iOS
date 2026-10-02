import XCTest
@testable import LineDrawCore

final class DeviceNavigationTests:XCTestCase {
    let bundle=DeviceScreenRules.lineBundle
    var url:String{TestCatalog.five()[0].canonicalURL!}
    func guardState()->DeviceNavigationGuard{
        var state=DeviceNavigationGuard(expectedBundle:bundle,targetURL:url);state.didOpen(at:0);return state
    }
    func screen(_ label:String,width:Double=400,height:Double=800)->DeviceScreen{
        // 展開的系統進度遮住關閉鈕，但底部操作區仍可使用。
        DeviceScreen(bundle:bundle,width:width,height:height,nodes:[
            .init(type:"XCUIElementTypeApplication",labels:["LINE"],rect:.init(x:0,y:0,width:width,height:height)),
            .init(type:"XCUIElementTypeWebView",labels:[],rect:.init(x:0,y:50,width:width,height:height-50)),
            .init(type:"XCUIElementTypeStaticText",labels:["LineDraw 抽選"],rect:.init(x:40,y:30,width:200,height:80)),
            .init(type:"XCUIElementTypeButton",labels:["關閉"],rect:.init(x:width-40,y:70,width:30,height:30)),
            .init(type:"XCUIElementTypeButton",labels:[label],rect:.init(x:0,y:height*0.85,width:width,height:height*0.1))
        ],targeted:true)
    }
    func testNoURLAckCannotAuthorizeEvenAReadyScreen(){
        var state=DeviceNavigationGuard(expectedBundle:bundle,targetURL:url)
        XCTAssertFalse(state.observe(screen("抽選"),at:1));XCTAssertFalse(state.observe(screen("抽選"),at:2))
    }
    func testCoveredCloseDoesNotBlockStableDrawOnDifferentPhoneSizes(){
        for (w,h) in [(375.0,667.0),(393.0,852.0),(440.0,956.0),(956.0,440.0)]{
            var state=guardState();let ready=screen("加入好友並參加抽獎",width:w,height:h)
            XCTAssertFalse(state.observe(ready,at:0.3));XCTAssertTrue(state.observe(ready,at:0.6))
            XCTAssertEqual(state.confirmation,"settled")
        }
    }
    func testRepeatedSameLayoutCanOpenConsecutiveDifferentURLs(){
        let ready=screen("抽選")
        for row in TestCatalog.five(){
            var state=DeviceNavigationGuard(expectedBundle:bundle,targetURL:row.canonicalURL!)
            state.didOpen(at:10)
            XCTAssertFalse(state.observe(ready,at:10.2));XCTAssertTrue(state.observe(ready,at:10.6))
        }
    }
    func testKnownResultsWorkWithoutExposedDocumentURLOrDismissal(){
        for label in ["恭喜中獎","可惜...沒有抽中！","查看已領取的優惠券","已結束"]{
            var state=guardState();var ready=screen(label)
            ready.nodes.append(.init(type:"XCUIElementTypeStaticText",labels:["官方帳號優惠券"],rect:.init(x:0,y:70,width:200,height:30)))
            XCTAssertFalse(state.observe(ready,at:0.2));XCTAssertTrue(state.observe(ready,at:0.6),label)
        }
    }
    func testTransientOldResultDoesNotAuthorizeNewDrawOrBecomeItsResult(){
        var state=guardState()
        XCTAssertFalse(state.observe(screen("查看已領取的優惠券"),at:0.1))
        XCTAssertFalse(state.observe(screen("抽選"),at:0.6))
        XCTAssertTrue(state.observe(screen("抽選"),at:0.9))
    }
    func testLandingAndObservationIntervalsBothRequired(){
        var state=guardState();let ready=screen("抽選")
        XCTAssertFalse(state.observe(ready,at:0.05));XCTAssertFalse(state.observe(ready,at:0.3))
        XCTAssertTrue(state.observe(ready,at:0.6))
        state.didOpen(at:5)
        XCTAssertFalse(state.observe(ready,at:5.6));XCTAssertFalse(state.observe(ready,at:5.65))
        XCTAssertTrue(state.observe(ready,at:5.9))
    }
    func testLoadingEmptyAndForeignAppResetCandidate(){
        for kind in ["loading","empty","foreign"]{
            var state=guardState();let ready=screen("抽選")
            XCTAssertFalse(state.observe(ready,at:0.3))
            var interrupted=screen("載入中")
            if kind=="empty"{interrupted.nodes=[]}
            if kind=="foreign"{interrupted.bundle="com.apple.springboard"}
            XCTAssertFalse(state.observe(interrupted,at:0.6))
            XCTAssertFalse(state.observe(ready,at:0.9));XCTAssertTrue(state.observe(ready,at:1.2))
        }
    }
    func testAlertsAndAmbiguousTargetsCannotAuthorize(){
        for kind in ["alert","ambiguous"]{
            var state=guardState();var s=screen("抽選")
            s.nodes.append(.init(type:kind=="alert" ? "XCUIElementTypeAlert":"XCUIElementTypeButton",labels:["立即抽獎"],rect:.init(x:10,y:650,width:200,height:40)))
            XCTAssertFalse(state.observe(s,at:0.3));XCTAssertFalse(state.observe(s,at:2))
        }
    }
    func testExplicitOtherDocumentIsNeverAcceptedByTime(){
        var state=guardState();var s=screen("抽選")
        s.nodes[1].labels=[TestCatalog.five()[1].canonicalURL!]
        XCTAssertFalse(state.observe(s,at:1));XCTAssertFalse(state.observe(s,at:20))
        s.nodes[1].labels=[url];XCTAssertTrue(state.observe(s,at:21))
        XCTAssertEqual(state.confirmation,"document")
    }
    func testReadinessResetsForReloadAndWrongDocumentStillBlocksAfterVerified(){
        var state=guardState();var s=screen("抽選");s.nodes[1].labels=[url]
        XCTAssertTrue(state.observe(s,at:1))
        s.nodes[1].labels=[TestCatalog.five()[1].canonicalURL!];XCTAssertFalse(state.observe(s,at:2))
        state.didOpen(at:3);s.nodes[1].labels=[]
        XCTAssertFalse(state.verified);XCTAssertFalse(state.observe(s,at:3.6))
        XCTAssertTrue(state.observe(s,at:3.9))
    }
    func testInvalidGeometryAndDisabledActionsDoNotBecomeReady(){
        var state=guardState();var s=screen("抽選");s.width = .nan
        XCTAssertFalse(state.observe(s,at:1));s=screen("抽選");s.nodes[s.nodes.count-1].enabled=false
        XCTAssertFalse(state.observe(s,at:2));XCTAssertFalse(state.observe(s,at:3))
    }
}
