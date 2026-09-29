#if DEBUG
import Foundation
import Network
import LineDrawCore

/// A loopback-only, synthetic coupon for cross-app testing in Safari.
/// No LINE URL, account, personal data, or external resource is used.
@MainActor final class DeviceProbeServer {
    private var listener:NWListener?
    private(set) var requests=0
    private(set) var acknowledged=Set<String>()
    private(set) var acknowledgementCounts=[String:Int]()
    private var ready=false
    private var failure:String?
    private let queue=DispatchQueue(label:"LineDraw.fixture")
    func start()async throws->String{
        let parameters=NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener=try NWListener(using:parameters);self.listener=listener
        listener.stateUpdateHandler={[weak self] state in Task{@MainActor in
            switch state {
            case .ready:self?.ready=true
            case .failed(let error):self?.failure="Fixture listener: \(error)"
            default:break
            }
        }}
        let token=UUID().uuidString
        listener.newConnectionHandler={[weak self] connection in
            connection.start(queue:DispatchQueue.global(qos:.utility))
            connection.receive(minimumIncompleteLength:1,maximumLength:8192){bytes,_,_,_ in
                guard let bytes,let raw=String(data:bytes,encoding:.utf8),raw.hasPrefix("GET /\(token)/") else{connection.cancel();return}
                let path=String(raw.split(separator:" ").dropFirst().first ?? "")
                let item=String(path.split(separator:"/").last ?? "").filter{$0.isASCII && ($0.isLetter || $0.isNumber)}
                if path.hasPrefix("/\(token)/ack/") {
                    Task{@MainActor [weak self] in self?.acknowledged.insert(item);self?.acknowledgementCounts[item,default:0] += 1}
                    connection.send(content:Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),completion:.contentProcessed{_ in connection.cancel()});return
                }
                Task{@MainActor [weak self] in self?.requests += 1}
                let page="""
                <!doctype html><html lang="zh-Hant"><head><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><title>LineDraw 離線驗證</title></head>
                <body style="margin:0;font-family:system-ui;background:#f7faff;color:#123"><header style="padding:24px;font-size:24px">官方帳號優惠券</header><main style="padding:24px"><h1>LineDraw 離線測試 \(item)</h1><p>這是手機本機測試畫面，不會送出任何真實抽選。</p><p>查看我的優惠券</p><p id="result">尚未操作</p></main><button style="position:fixed;bottom:20px;left:12px;right:12px;height:72px;border:0;border-radius:20px;background:#1674df;color:white;font-size:24px" onclick="fetch('/\(token)/ack/\(item)',{cache:'no-store'});document.getElementById('result').textContent='恭喜中獎';this.textContent='查看已領取的優惠券';this.disabled=true">抽選</button></body></html>
                """
                let body=Data(page.utf8);var response=Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8);response.append(body)
                connection.send(content:response,completion:.contentProcessed{_ in connection.cancel()})
            }
        }
        listener.start(queue:queue)
        for _ in 0..<50 {try Task.checkCancellation();if let failure{throw LineDrawError.message(failure)};if ready,let port=listener.port{return "http://127.0.0.1:\(port.rawValue)/\(token)/"};try await Task.sleep(for:.milliseconds(100))}
        listener.cancel();throw LineDrawError.message("本機測試網頁無法啟動。")
    }
    func stop(){listener?.cancel();listener=nil}
}
#endif
