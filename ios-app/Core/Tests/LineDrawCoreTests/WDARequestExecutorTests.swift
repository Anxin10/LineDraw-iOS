import XCTest
@testable import LineDrawCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class WDARequestExecutorTests:XCTestCase {
    func request(_ method:String="GET",_ suffix:String="source")->URLRequest{
        var request=URLRequest(url:URL(string:"http://127.0.0.1:52000/session/private-session/"+suffix)!)
        request.httpMethod=method;request.timeoutInterval=12;return request
    }
    func response(_ request:URLRequest)->(Data,URLResponse){(Data("fresh".utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)}
    func testTimedOutSnapshotRetriesWithFreshResponseAndBoundedBudgets()async throws{
        var deadlines=[TimeInterval](),events=[WDARequestAttempt]()
        let (data,_)=try await WDARequestExecutor.execute(request(),send:{request in
            deadlines.append(request.timeoutInterval)
            if deadlines.count==1{throw URLError(.timedOut)}
            return self.response(request)
        },onAttempt:{events.append($0)})
        XCTAssertEqual(String(data:data,encoding:.utf8),"fresh")
        XCTAssertEqual(deadlines.count,2);XCTAssertLessThanOrEqual(deadlines.reduce(0,+),30)
        XCTAssertEqual(events.map(\.timedOut),[true,false]);XCTAssertEqual(events.map(\.operation),["GET source","GET source"])
    }
    func testActionTimeoutsNeverReplayTapNavigationOrSessionCreation()async{
        var creation=URLRequest(url:URL(string:"http://127.0.0.1:52000/session")!)
        creation.httpMethod="POST";creation.timeoutInterval=12
        let actions=[creation]+["wda/tap","url","source","appium/settings"].map{request("POST",$0)}
        for action in actions {
            var calls=0
            do{_=try await WDARequestExecutor.execute(action,send:{_ in calls+=1;throw URLError(.timedOut)});XCTFail("Expected timeout")}
            catch{XCTAssertEqual((error as NSError).code,NSURLErrorTimedOut)}
            XCTAssertEqual(calls,1,WDARequestExecutor.operation(action))
        }
    }
    func testPersistentReadTimeoutStopsAfterOneRetry()async{
        var calls=0
        do{_=try await WDARequestExecutor.execute(request(),send:{_ in calls+=1;throw URLError(.timedOut)});XCTFail("Expected timeout")}
        catch{XCTAssertEqual((error as NSError).code,NSURLErrorTimedOut)}
        XCTAssertEqual(calls,2)
    }
    func testNonTimeoutReadFailureAndOtherReadsDoNotRetry()async{
        for (suffix,code) in [("source",URLError.Code.networkConnectionLost),("window/size",.timedOut)] {
            var calls=0
            do{_=try await WDARequestExecutor.execute(request("GET",suffix),send:{_ in calls+=1;throw URLError(code)});XCTFail("Expected error")}
            catch{XCTAssertEqual((error as NSError).code,code.rawValue)}
            XCTAssertEqual(calls,1)
        }
    }
    func testTransientHTTPFailuresRetryOnlyScreenReads()async throws{
        for suffix in ["source","wda/activeAppInfo"] {
            var calls=0
            _=try await WDARequestExecutor.execute(request("GET",suffix),send:{r in
                calls+=1
                if calls==1{throw WDAResponseFailure(operation:"GET "+suffix,status:500,code:"unknown error",remoteMessage:"snapshot unavailable")}
                return self.response(r)
            })
            XCTAssertEqual(calls,2)
        }
        for method in ["POST","DELETE"] {
            var calls=0
            do{_=try await WDARequestExecutor.execute(request(method,"wda/tap"),send:{_ in
                calls+=1;throw WDAResponseFailure(operation:"POST wda/tap",status:500,code:"unknown error",remoteMessage:"outcome unknown")
            });XCTFail("Expected failure")}catch{}
            XCTAssertEqual(calls,1)
        }
    }
    func testPersistentHTTPFailuresBoundedAndInvalidSessionNeverRetried()async {
        for (code,status,expected) in [("unknown error",500,2),("invalid JSON",502,2),("invalid session id",404,1),("invalid argument",400,1)] {
            var calls=0
            do{_=try await WDARequestExecutor.execute(request(),send:{_ in
                calls+=1;throw WDAResponseFailure(operation:"GET source",status:status,code:code,remoteMessage:"")
            });XCTFail("Expected failure")}catch{}
            XCTAssertEqual(calls,expected)
        }
    }
    func testCancellationBetweenReadAttemptsPreventsRetry()async{
        var calls=0
        let work=Task{
            try await WDARequestExecutor.execute(request(),send:{_ in
                calls+=1
                withUnsafeCurrentTask{$0?.cancel()}
                throw URLError(.timedOut)
            })
        }
        do{_=try await work.value;XCTFail("Expected cancellation")}
        catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(calls,1)
    }
    func testCancelledTaskRejectsLateSuccessfulScreenResponse()async{
        var calls=0
        let work=Task{
            try await WDARequestExecutor.execute(request(),send:{request in
                calls+=1
                withUnsafeCurrentTask{$0?.cancel()}
                return self.response(request)
            })
        }
        do{_=try await work.value;XCTFail("Cancelled work must not return a screen for a later tap")}
        catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(calls,1)
    }
}
