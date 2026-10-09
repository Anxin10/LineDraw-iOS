import Foundation
import Security
import CryptoKit
import LineDrawCore

struct KeychainStore {
    static let service="com.anxin10.linedraw.ios.companion"
    static func save(_ data:Data)throws{
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"pairing",kSecAttrSynchronizable as String:false]
        let update=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if update==errSecItemNotFound{var item=query;item[kSecValueData as String]=data;item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else{throw LineDrawError.message("無法安全儲存配對資料。")}}
        else if update != errSecSuccess{throw LineDrawError.message("無法更新配對資料。")}
    }
    static func read()throws->PairingCredential?{
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"pairing",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var value:CFTypeRef?;let result=SecItemCopyMatching(query as CFDictionary,&value)
        if result==errSecItemNotFound{return nil};guard result==errSecSuccess,let data=value as? Data else{throw LineDrawError.message("配對資料無法讀取。")}
        return try WireJSON.decoder().decode(PairingCredential.self,from:data)
    }
    static func clear(){SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"pairing"] as CFDictionary)}
}
final class PinnedSession:NSObject,URLSessionDelegate,URLSessionTaskDelegate,@unchecked Sendable{
    let fingerprint:String;let host:String
    init(fingerprint:String,host:String){self.fingerprint=fingerprint;self.host=host}
    func urlSession(_ session:URLSession,didReceive challenge:URLAuthenticationChallenge,completionHandler:@escaping(URLSession.AuthChallengeDisposition,URLCredential?)->Void){
        guard challenge.protectionSpace.authenticationMethod==NSURLAuthenticationMethodServerTrust,challenge.protectionSpace.host==host,let trust=challenge.protectionSpace.serverTrust,let certificates=SecTrustCopyCertificateChain(trust) as? [SecCertificate],let certificate=certificates.first else{completionHandler(.cancelAuthenticationChallenge,nil);return}
        let data=SecCertificateCopyData(certificate) as Data
        let actual=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        // Trust only the exact leaf certificate displayed on the user's Mac, never all self-signed certificates.
        guard actual==fingerprint else{completionHandler(.cancelAuthenticationChallenge,nil);return}
        completionHandler(.useCredential,URLCredential(trust:trust))
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}
final class CompanionClient:@unchecked Sendable{
    private struct Failure:Decodable{var error:String?}
    let credential:PairingCredential;let session:URLSession;let delegate:PinnedSession
    init(_ credential:PairingCredential)throws{
        guard PairingInvitation.localEndpoint(credential.endpoint),let host=URL(string:credential.endpoint)?.host else{throw LineDrawError.message("Mac 位址不正確。")}
        self.credential=credential;delegate=PinnedSession(fingerprint:credential.fingerprint,host:host)
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=20;config.httpCookieStorage=nil;config.urlCache=nil;config.waitsForConnectivity=false
        session=URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
    }
    deinit{session.invalidateAndCancel()}
    func send<T:Decodable>(_ path:String,body:Data?=nil) async throws->T{
        let request:URLRequest=try makeRequest(path,body:body)
        let (bytes,response)=try await session.bytes(for:request)
        guard let response=response as? HTTPURLResponse else{throw LineDrawError.message("Mac 回應異常。")}
        var data=Data();for try await b in bytes{guard data.count<2_000_000 else{throw LineDrawError.message("Mac 回應過大。")};data.append(b)}
        guard response.statusCode==200 else{
            let message=(try? JSONDecoder().decode(Failure.self,from:data).error) ?? "無法連線 Mac，請檢查配對與網路。"
            throw LineDrawError.message(message)
        }
        return try WireJSON.decoder().decode(T.self,from:data)
    }
    private func makeRequest(_ path:String,body:Data?)throws->URLRequest{
        guard let url=URL(string:credential.endpoint+path) else{throw LineDrawError.message("Mac 位址不正確。")}
        var request=URLRequest(url:url);request.httpMethod=body==nil ? "GET":"POST";request.httpBody=body
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if !credential.token.isEmpty{request.setValue("Bearer "+credential.token,forHTTPHeaderField:"Authorization")};return request
    }
    static func pair(_ invitation:PairingInvitation) async throws->PairingCredential{
        let initial=PairingCredential(endpoint:invitation.endpoint,fingerprint:invitation.fingerprint,token:"",name:"")
        let client=try CompanionClient(initial)
        struct Reply:Decodable{var token:String;var name:String}
        let reply:Reply=try await client.send("/v1/pair",body:JSONSerialization.data(withJSONObject:["code":invitation.code]))
        guard reply.token.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil else{throw LineDrawError.message("配對回應異常。")}
        return PairingCredential(endpoint:invitation.endpoint,fingerprint:invitation.fingerprint,token:reply.token,name:reply.name)
    }
    func status(profile:String,area:DrawArea)async throws->CompanionStatus{
        var components=URLComponents();components.queryItems=[URLQueryItem(name:"profile",value:profile),URLQueryItem(name:"area",value:area.rawValue)]
        return try await send("/v1/status?"+(components.percentEncodedQuery ?? ""))
    }
    func start(_ start:CompanionStart)async throws->CompanionStatus{try await send("/v1/start",body:WireJSON.encoder().encode(start))}
    func control(_ action:String,profile:String,area:DrawArea)async throws->CompanionStatus{try await send("/v1/"+action,body:JSONSerialization.data(withJSONObject:["profile":profile,"area":area.rawValue]))}
    func mutate(_ mutations:[RecordMutation])async throws{
        struct Reply:Decodable{var ok:Bool}
        let _:Reply=try await send("/v1/records",body:WireJSON.encoder().encode(mutations))
    }
    func catalog()async throws->[Draw]{try await send("/v1/catalog")}
    func unpair()async throws{struct Reply:Decodable{var ok:Bool};let _:Reply=try await send("/v1/unpair",body:Data("{}".utf8))}
}
