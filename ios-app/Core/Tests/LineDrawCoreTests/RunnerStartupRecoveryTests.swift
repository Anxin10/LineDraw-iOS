import XCTest
@testable import LineDrawCore

final class RunnerStartupRecoveryTests:XCTestCase {
    func testOnlyFirstPreCommandStartupFailureCanRetry(){
        XCTAssertTrue(RunnerStartupRecovery.shouldRetry(code:"XCTEST_SESSION_FAILED",attempt:0,cancelled:false,appActive:true,sessionEstablished:false))
        XCTAssertFalse(RunnerStartupRecovery.shouldRetry(code:"XCTEST_SESSION_FAILED",attempt:1,cancelled:false,appActive:true,sessionEstablished:false))
        XCTAssertFalse(RunnerStartupRecovery.shouldRetry(code:"XCTEST_SESSION_FAILED",attempt:0,cancelled:true,appActive:true,sessionEstablished:false))
        XCTAssertFalse(RunnerStartupRecovery.shouldRetry(code:"XCTEST_SESSION_FAILED",attempt:0,cancelled:false,appActive:false,sessionEstablished:false))
        XCTAssertFalse(RunnerStartupRecovery.shouldRetry(code:"XCTEST_SESSION_FAILED",attempt:0,cancelled:false,appActive:true,sessionEstablished:true))
        for code in ["RP_CONNECT_TIMEOUT","PAIRING_REJECTED","RUNNER_NOT_INSTALLED","DDI_REQUIRED","HEARTBEAT_LOST","READY"] {
            XCTAssertFalse(RunnerStartupRecovery.shouldRetry(code:code,attempt:0,cancelled:false,appActive:true,sessionEstablished:false))
        }
    }
}
