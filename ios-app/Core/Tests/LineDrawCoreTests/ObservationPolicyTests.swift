import XCTest
@testable import LineDrawCore

final class ObservationPolicyTests:XCTestCase {
    func testNavigationPreservesDeadlineAndItemIdentity()throws {
        let context=QueryContext(deadline:30),next=context.navigating()
        XCTAssertEqual(context.itemID,next.itemID);XCTAssertNotEqual(context.navigationID,next.navigationID)
        XCTAssertEqual(try next.timeout(cap:12,now:0),12)
        XCTAssertEqual(try next.timeout(cap:12,now:29),1)
        XCTAssertThrowsError(try next.timeout(cap:12,now:30))
    }
    func testAttemptsBoundedAcrossFallbacks()throws {
        var policy=ObservationPolicy()
        for _ in 0..<6{try policy.consume(.targeted)}
        XCTAssertThrowsError(try policy.consume(.targeted));XCTAssertTrue(policy.shouldUseXML)
        try policy.consume(.xml);try policy.consume(.xml)
        XCTAssertThrowsError(try policy.consume(.xml))
        try policy.consume(.ocr);try policy.consume(.ocr)
        XCTAssertThrowsError(try policy.consume(.ocr))
    }
    func testIncompleteNeedsTwoObservations() {
        var policy=ObservationPolicy();policy.recordIncomplete();XCTAssertFalse(policy.shouldUseXML)
        policy.recordIncomplete();XCTAssertTrue(policy.shouldUseXML)
        policy.recordComplete();XCTAssertFalse(policy.shouldUseXML)
    }
}
final class XMLScreenParserTests:XCTestCase {
    let start="<XCUIElementTypeApplication x=\"0\" y=\"0\" width=\"400\" height=\"800\" visible=\"true\">"
    let end="</XCUIElementTypeApplication>"
    func testCompleteGeometryAndExplicitState()throws {
        let button="<XCUIElementTypeButton label=\"抽選\" x=\"0\" y=\"700\" width=\"400\" height=\"60\" visible=\"true\" enabled=\"true\"/>"
        let nodes=try XMLScreenParser.parse(start+button+end)
        XCTAssertTrue(nodes[1].enabled)
        let missing=try XMLScreenParser.parse(start+button.replacingOccurrences(of:" enabled=\"true\"",with:"")+end)
        XCTAssertFalse(missing[1].enabled)
    }
    func testIncompleteUnsafeAndInvalidGeometryRejected() {
        for xml in [start,"<!DOCTYPE x>"+start+end,"<!ENTITY x 'y'>"+start+end,start.replacingOccurrences(of:"400",with:"nan")+end,"<x/>"] {
            XCTAssertThrowsError(try XMLScreenParser.parse(xml))
        }
    }
    func testDepthNodeAttributeAndByteLimits() {
        var limits=XMLParseLimits();limits.depth=1
        XCTAssertThrowsError(try XMLScreenParser.parse(start+"<x/>"+end,limits:limits))
        limits=XMLParseLimits();limits.nodes=1
        XCTAssertThrowsError(try XMLScreenParser.parse(start+"<x/>"+end,limits:limits))
        limits=XMLParseLimits();limits.attributeBytes=2
        XCTAssertThrowsError(try XMLScreenParser.parse(start+end,limits:limits))
        limits=XMLParseLimits();limits.bytes=8
        XCTAssertThrowsError(try XMLScreenParser.parse(start+end,limits:limits))
    }
    func testCancellationNeverReturnsPartialNodes() {
        XCTAssertThrowsError(try XMLScreenParser.parse(start+end,cancelled:{true})) { XCTAssertTrue($0 is CancellationError) }
    }
}
