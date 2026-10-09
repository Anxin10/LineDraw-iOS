import XCTest
@testable import LineDrawCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class WDAResponseTests:XCTestCase {
    func testLockedOpenURLExplainsPauseWithoutExposingRemoteMessage(){
        let error=WDAResponseFailure(operation:"POST url",status:500,code:"unknown error",remoteMessage:"private details: unable to launch because the device is locked")
        XCTAssertTrue(error.localizedDescription.contains("iPhone 已鎖定"))
        XCTAssertFalse(error.localizedDescription.contains("private details"))
        let action=WDAResponseFailure(operation:"POST wda/tap",status:500,code:"unknown error",remoteMessage:"device is locked")
        XCTAssertFalse(action.localizedDescription.contains("請解鎖後重新開始"))
    }
    func decode(_ body:String,status:Int=200,operation:String="GET source")throws->Any {
        try WDAResponse.decode(Data(body.utf8),response:HTTPURLResponse(url:URL(string:"http://127.0.0.1/session/test/source")!,statusCode:status,httpVersion:nil,headerFields:nil)!,operation:operation)
    }
    func testWDAErrorIsDecodedBeforeHTTPFailureAndDoesNotExposeRemoteMessage()throws {
        XCTAssertThrowsError(try decode(#"{"value":{"error":"unknown error","message":"private application description"}}"#,status:500)){error in
            let error=error as! WDAResponseFailure
            XCTAssertEqual(error.operation,"GET source");XCTAssertEqual(error.status,500)
            XCTAssertEqual(error.code,"unknown error");XCTAssertEqual(error.remoteMessage,"private application description")
            XCTAssertFalse(error.localizedDescription.contains("private application description"))
        }
    }
    func testActionAcknowledgementMayContainNullButValueMustExist()throws {
        XCTAssertTrue(try decode(#"{"value":null}"#,operation:"POST wda/tap") is NSNull)
        XCTAssertThrowsError(try decode(#"{"value":null}"#))
        XCTAssertThrowsError(try decode(#"{"sessionId":"test"}"#))
        XCTAssertThrowsError(try decode("<html>proxy failure</html>",status:502))
        XCTAssertThrowsError(try decode(#"{"value":{"error":"invalid session id","message":"gone"}}"#,status:404))
        XCTAssertThrowsError(try decode(#"{"value":{"error":"unknown error","message":"failed"}}"#))
    }
}
