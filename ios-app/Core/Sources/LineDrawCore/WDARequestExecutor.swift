import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WDARequestAttempt:Sendable {
    public let operation:String
    public let attempt:Int
    public let seconds:Double
    public let errorCode:Int?
    public let timedOut:Bool
}

/// A screen query is read-only and may safely be repeated after an AX timeout.
/// Action requests have unknown outcomes on timeout and must never be replayed here.
@MainActor public enum WDARequestExecutor {
    public static func operation(_ request:URLRequest)->String {
        let parts=request.url?.path.split(separator:"/") ?? []
        let suffix=parts.first=="session" ? (parts.count>2 ? parts.dropFirst(2).joined(separator:"/"):"session"):parts.joined(separator:"/")
        let format=URLComponents(url:request.url ?? URL(string:"http://localhost")!,resolvingAgainstBaseURL:false)?.queryItems?.first{$0.name=="format"}?.value
        return (request.httpMethod ?? "GET")+" "+suffix+(suffix=="source" && format=="json" ? ".json":"")
    }
    public static func execute(_ request:URLRequest,
        context:QueryContext?=nil,
        clock:()->TimeInterval={ProcessInfo.processInfo.systemUptime},
        send:(URLRequest)async throws->(Data,URLResponse),
        onAttempt:(WDARequestAttempt)->Void={_ in}
    )async throws->(Data,URLResponse) {
        let method=request.httpMethod ?? "GET"
        let parts=request.url?.path.split(separator:"/") ?? []
        let screenRead=method=="GET" && parts.count==3 && parts[0]=="session" && parts[2]=="source"
        let appRead=method=="GET" && parts.count==4 && parts[0]=="session" && parts[2]=="wda" && parts[3]=="activeAppInfo"
        // The combined screen-read budget stays close to the queue's 30-second load window.
        let deadlines: [TimeInterval]=context != nil ? [request.timeoutInterval] : screenRead ? [18,12]:appRead ? [min(request.timeoutInterval,12),min(request.timeoutInterval,8)]:[request.timeoutInterval]
        for (index,timeout) in deadlines.enumerated() {
            try Task.checkCancellation()
            // Do not dispatch a new bounded read with a sub-second deadline.
            // Budget exhaustion before sending is safe to advance; an actual
            // in-flight timeout still propagates and must stop the transport.
            var attempt=request;attempt.timeoutInterval=try context?.timeout(cap:timeout,now:clock(),minimum:method=="GET" ? 1:0) ?? timeout
            let began=ProcessInfo.processInfo.systemUptime
            let result:(Data,URLResponse)
            do {
                result=try await send(attempt)
            }catch {
                let ns=error as NSError
                let timedOut=ns.domain==NSURLErrorDomain && ns.code==NSURLErrorTimedOut
                onAttempt(.init(operation:operation(request),attempt:index+1,seconds:ProcessInfo.processInfo.systemUptime-began,errorCode:ns.code,timedOut:timedOut))
                try Task.checkCancellation()
                let transientResponse=(error as? WDAResponseFailure)?.canRetryRead==true
                if (screenRead || appRead),(timedOut || transientResponse),index+1<deadlines.count{
                    if transientResponse{try await Task.sleep(for:.milliseconds(200))}
                    continue
                }
                throw error
            }
            onAttempt(.init(operation:operation(request),attempt:index+1,seconds:ProcessInfo.processInfo.systemUptime-began,errorCode:nil,timedOut:false))
            try Task.checkCancellation();if let context{_=try context.timeout(cap:1,now:clock())};return result
        }
        preconditionFailure("At least one request attempt is required")
    }
}
