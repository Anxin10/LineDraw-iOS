import Foundation

/// Only the pre-command XCTest startup failure is eligible. Never retry an
/// established session, cancelled work, pairing, transport or signing errors.
public enum RunnerStartupRecovery {
    public static func shouldRetry(code:String,attempt:Int,cancelled:Bool,appActive:Bool,sessionEstablished:Bool)->Bool {
        code=="XCTEST_SESSION_FAILED" && attempt==0 && !cancelled && appActive && !sessionEstablished
    }
}
