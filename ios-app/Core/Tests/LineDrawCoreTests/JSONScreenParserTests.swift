import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LineDrawCore

final class JSONScreenParserTests:XCTestCase{
    func tree(label:String="參加抽獎",enabled:String?="1")->[String:Any]{
        var child:[String:Any]=["type":"Button","label":label,"rect":["x":0,"y":720,"width":400,"height":80],"isVisible":"1"]
        child["isEnabled"]=enabled
        return ["type":"Application","rect":["x":0,"y":0,"width":400,"height":800],"isVisible":"1","isEnabled":"1","children":[child]]
    }
    func parse(_ tree:[String:Any],limits:XMLParseLimits=XMLParseLimits())throws->[ScreenNode]{try JSONScreenParser.parse(JSONSerialization.data(withJSONObject:tree),limits:limits)}
    func testJSONActionUsesNativeCoordinatesAndState()throws{
        let nodes=try parse(tree());let screen=DeviceScreen(bundle:DeviceScreenRules.lineBundle,width:400,height:800,nodes:nodes)
        guard case .click("SUBMIT",let node)=DeviceScreenRules.classify(screen) else{return XCTFail("Expected known button")}
        XCTAssertEqual(node.rect.y,720);XCTAssertFalse(node.ocr)
    }
    func testMissingEnabledDoesNotAuthorizeAction()throws{
        let nodes=try parse(tree(enabled:nil));XCTAssertFalse(nodes.last!.enabled)
    }
    func testHiddenParentCannotExposeButton()throws{
        var root=tree();root["isVisible"]="0";XCTAssertTrue(try parse(root).isEmpty)
    }
    func testNodeAndByteLimitsRejectTree()throws{
        var limits=XMLParseLimits();limits.nodes=1;XCTAssertThrowsError(try parse(tree(),limits:limits))
        limits=XMLParseLimits();limits.bytes=2;XCTAssertThrowsError(try parse(tree(),limits:limits))
    }
    func testMalformedChildrenRejected()throws{
        var root=tree();root["children"]=["bad"];XCTAssertThrowsError(try parse(root))
    }
    func testExistingSettingsDecodeWithoutNewLookupField()throws{
        let old:[String:Any]=["profile":"預設","profiles":["預設"],"autoFriend":true,"autoContinue":true,"appearance":"system","reduceTransparency":false,"reduceMotion":false]
        let decoded=try JSONDecoder().decode(AppSettings.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertNil(decoded.scanLookupMode);XCTAssertNil(decoded.batchLookupMode);XCTAssertEqual(decoded.profile,"預設")
    }
    @MainActor func testNativeJSONResponseIsDistinctFromXMLResponse()async throws{
        let url=URL(string:"http://localhost/session/id/source?format=json")!
        let request=URLRequest(url:url)
        XCTAssertEqual(WDARequestExecutor.operation(request),"GET source.json")
        let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!
        let body=try JSONSerialization.data(withJSONObject:["value":tree()])
        XCTAssertTrue(try WDAResponse.decode(body,response:response,operation:"GET source.json") is [String:Any])
        XCTAssertThrowsError(try WDAResponse.decode(body,response:response,operation:"GET source"))
    }
}
