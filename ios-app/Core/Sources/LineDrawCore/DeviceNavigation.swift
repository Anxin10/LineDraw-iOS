import Foundation

/// 深連結成功送出後確認畫面就緒。LINE 可能在同一個 WebView 內換頁，
/// 不提供網址或關閉動畫，因此換頁不能依賴可能被系統進度遮住的關閉鈕。
/// 沒有頁面網址時，以有限的畫面觀察判斷就緒，不代表已證實優惠券身分；
/// 載入期限仍由批次流程管理。
public struct DeviceNavigationGuard:Sendable {
    public let expectedBundle:String
    public let targetURL:String
    public private(set) var verified=false
    public private(set) var confirmation="pending"
    private var openedAt:TimeInterval?
    private var candidate=""
    private var candidateAt:TimeInterval=0
    public init(expectedBundle:String,targetURL:String){self.expectedBundle=expectedBundle;self.targetURL=targetURL}
    /// 只在 WDA 成功回應開網址指令後呼叫，不能在送出前啟用。
    public mutating func didOpen(at now:TimeInterval){
        openedAt=now;verified=false;confirmation="pending";candidate="";candidateAt=0
    }
    public mutating func observe(_ screen:DeviceScreen,at now:TimeInterval=ProcessInfo.processInfo.systemUptime)->Bool {
        guard let openedAt,now>=openedAt,screen.bundle==expectedBundle,
              screen.width.isFinite,screen.height.isFinite,screen.width>0,screen.height>0 else{candidate="";return false}
        let decision=DeviceScreenRules.classify(screen,expectedBundle:expectedBundle)
        // 明確的結束提示框可完成換頁驗證；其他提示框仍不能當成新券就緒。
        if screen.nodes.contains(where:{$0.type=="XCUIElementTypeAlert"}),decision != .terminal("ENDED"){candidate="";return false}
        // LINE 若提供完整活動網址，明確不同的優惠券不能靠等待時間
        // 或相同按鈕文字通過檢查。
        let documents=screen.nodes.filter{$0.type=="XCUIElementTypeWebView"}
            .flatMap(\.labels).compactMap{LinkPolicy.canonical($0)}
        if documents.contains(where:{$0 != targetURL}){candidate="";return false}
        if documents.contains(targetURL){verified=true;confirmation="document";return true}
        if verified{return true}
        switch decision {
        case .click,.terminal:break
        default:candidate="";return false
        }
        // 網址回應後需跨過短暫載入期間，並取得兩次相符的新觀察。
        // 第一個畫面的舊結果或按鈕不能直接授權操作；不做頂部 OCR、
        // 關閉手勢或固定座標點擊。
        let key=DeviceScreenRules.stabilityKey(screen,decision:decision)
        if candidate != key{candidate=key;candidateAt=now;return false}
        guard now-openedAt>=0.5,now-candidateAt>=0.2 else{return false}
        verified=true;confirmation="settled";return true
    }
}
