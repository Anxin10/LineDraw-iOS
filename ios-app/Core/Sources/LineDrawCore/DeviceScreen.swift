import Foundation
import CoreGraphics
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ScreenRect: Equatable, Sendable, Codable {
    public var x:Double;public var y:Double;public var width:Double;public var height:Double
    public init(x:Double,y:Double,width:Double,height:Double){self.x=x;self.y=y;self.width=width;self.height=height}
    public func near(_ other:Self)->Bool{abs(x-other.x)<8 && abs(y-other.y)<8 && abs(width-other.width)<8 && abs(height-other.height)<8}
    public func isInside(width:Double,height:Double)->Bool {
        [x,y,self.width,self.height,width,height].allSatisfy(\.isFinite) &&
        self.width>0 && self.height>0 && width>0 && height>0 &&
        x>=0 && y>=0 && x+self.width<=width+1 && y+self.height<=height+1
    }
    public static func fromVision(_ box:CGRect,region:CGRect,width:Double,height:Double)->Self{
        // Vision observations are normalized to the requested region, not the whole image.
        Self(x:(region.minX+box.minX*region.width)*width,
             y:(1-region.minY-box.maxY*region.height)*height,
             width:box.width*region.width*width,height:box.height*region.height*height)
    }
    func contains(_ r:Self)->Bool{r.x>=x && r.y>=y && r.x+r.width<=x+width+1 && r.y+r.height<=y+height+1}
}
public struct ScreenNode: Equatable, Sendable {
    public var type:String;public var labels:[String];public var rect:ScreenRect;public var enabled:Bool;public var ocr:Bool
    public init(type:String,labels:[String],rect:ScreenRect,enabled:Bool=true,ocr:Bool=false){self.type=type;self.labels=labels;self.rect=rect;self.enabled=enabled;self.ocr=ocr}
}
public struct DeviceScreen:Sendable {
    public var bundle:String;public var width:Double;public var height:Double;public var nodes:[ScreenNode]
    public var targeted:Bool
    public var navigationVerified:Bool
    public var navigationPending:Bool
    public init(bundle:String,width:Double,height:Double,nodes:[ScreenNode],targeted:Bool=false,navigationVerified:Bool=false,navigationPending:Bool=false){self.bundle=bundle;self.width=width;self.height=height;self.nodes=nodes;self.targeted=targeted;self.navigationVerified=navigationVerified;self.navigationPending=navigationPending}
    public var fingerprint:String{LinkPolicy.digest(nodes.filter{!["XCUIElementTypeApplication","XCUIElementTypeWindow"].contains($0.type)}.map{"\($0.type)|\($0.labels)|\($0.rect)|\($0.enabled)"}.joined(separator:"\n"))}
    /// Shared by full XML and targeted observations. Changing lookup strategy is
    /// not evidence that the previous coupon has disappeared.
    public var navigationFingerprint:String {
        let rows=nodes.compactMap { node->String? in
            let labels=Array(Set(node.labels.filter(DeviceScreenRules.isRelevant).map(DeviceScreenRules.normalize))).sorted()
            guard !labels.isEmpty || node.type=="XCUIElementTypeAlert" else{return nil}
            return "\(node.type)|\(labels)|\(node.rect)|\(node.enabled)"
        }.sorted()
        return LinkPolicy.digest(([bundle,"\(width)x\(height)"]+rows).joined(separator:"\n"))
    }
}
public enum ScreenDecision:Equatable,Sendable {case wait, pause(String), terminal(String), click(String,ScreenNode), reopen}
public enum DeviceScreenRules {
    public static let lineBundle="jp.naver.line"
    public static func normalize(_ text:String)->String{text.precomposedStringWithCompatibilityMapping.filter{!$0.isWhitespace}.trimmingCharacters(in:CharacterSet(charactersIn:"!！。.…"))}
    public static let submit=["參加抽選","立即抽選","挑戰抽獎","立即抽獎","參加抽獎","抽獎","抽選"]
    public static let combined=["加入好友並抽選","加入好友並抽獎","加入好友並參加抽獎"]
    public static var actions:[String]{submit+combined+["加入好友"]}
    public static let couponHeaders=["官方帳號優惠券","查看我的優惠券"]
    public static let claimed=["使用優惠券","查看已領取的優惠券"]
    public static let participated=["您已參加過此抽選","已參加過抽獎","已抽過"]
    public static let completed=["恭喜中獎","恭喜您中獎了","恭喜獲得優惠券","很可惜，未中獎","未中獎","未抽中","銘謝惠顧","抽選完成","抽獎完成"]
    public static let blockers=["驗證碼","验证码","captcha","登入","登录","解除封鎖","授權存取","同意條款","付款"]
    public static var observationLabels:[String]{actions+couponHeaders+claimed+participated+completed+["已結束","可惜...沒有抽中！","官方帳號","已加入好友","聊天","關閉","Close","关闭"]}
    private static let normalizedObservationLabels=Set(observationLabels.map(normalize))
    private static let normalizedBlockers=blockers.map(normalize)
    public static func isRelevant(_ text:String)->Bool {
        let value=normalize(text)
        return normalizedObservationLabels.contains(value) || normalizedBlockers.contains{value.lowercased().contains($0)}
    }
    public static func acceptsOCR(_ text:String,confidence:Float,hasCouponContext:Bool)->Bool {
        if confidence>=0.9{return true}
        // Vision reports 0.5 for the correctly rendered two-character Chinese
        // fixture button. Lower confidence requires native coupon context plus
        // an exact known action/result; two observations and a fresh pre-tap
        // OCR still apply. Unknown words never receive this allowance.
        guard hasCouponContext,confidence>=0.5 else{return false}
        let allowed=actions+claimed+["已結束"]
        return allowed.contains{normalize($0)==normalize(text)}
    }
    public static func stabilityKey(_ screen:DeviceScreen,decision:ScreenDecision)->String {
        // Unrelated product text/animation must not reset an already stable target.
        // Navigation is checked separately, against navigationFingerprint.
        let prefix="\(screen.bundle)|\(screen.width)x\(screen.height)|"
        // Result recognition never taps. Carousel/layout motion elsewhere on
        // a verified coupon must not reset two matching terminal observations.
        if case .terminal(let status)=decision{return prefix+"terminal:"+status}
        if case .click(let action,let node)=decision {
            let labels=Array(Set(node.labels.map(normalize).filter{value in actions.contains{normalize($0)==value}})).sorted()
            return prefix+"\(action)|\(node.type)|\(labels)|\(node.rect)|\(node.enabled)|\(node.ocr)"
        }
        return prefix+"\(decision)|"+screen.navigationFingerprint
    }
    public static func allowsSingleObservation(_ screen:DeviceScreen,decision:ScreenDecision)->Bool {
        guard screen.navigationVerified,case .click(_,let node)=decision,
              !node.ocr,node.type=="XCUIElementTypeButton",node.enabled,
              node.rect.isInside(width:screen.width,height:screen.height),node.rect.y>=screen.height*0.60,
              screen.nodes.flatMap(\.labels).contains(where:{couponHeaders.map(normalize).contains(normalize($0))}) else{return false}
        return true
    }
    static func matches(_ screen:DeviceScreen,_ labels:[String],bottom:Bool=true,disabled:Bool=false)->[ScreenNode]{
        let names=labels.map(normalize)
        let eligible=screen.nodes.filter{n in (n.enabled || disabled) && n.rect.isInside(width:screen.width,height:screen.height) && n.labels.contains{names.contains(normalize($0))}}
        var list=eligible.filter{(!bottom || $0.rect.y>=screen.height*0.60) && (!$0.ocr || $0.rect.y>=screen.height*0.60)}
        // Expanded layouts are accepted only after a full read establishes the
        // coupon context. OCR and the fast path never authorize upper-page taps.
        if list.isEmpty,bottom,!screen.targeted,
           screen.nodes.flatMap(\.labels).contains(where:{label in couponHeaders.contains{normalize($0)==normalize(label)}}) {
            list=eligible.filter{!$0.ocr && $0.type=="XCUIElementTypeButton" && $0.rect.y>=screen.height*0.22}
        }
        var seen=[ScreenNode]()
        for n in list where !list.contains(where:{$0.type=="XCUIElementTypeButton" && n.type != $0.type && $0.rect.contains(n.rect)}) {
            if !seen.contains(where:{$0.rect==n.rect && $0.labels.contains{l in n.labels.map(normalize).contains(normalize(l))}}){seen.append(n)}
        };return seen
    }
    public static func classify(_ screen:DeviceScreen,expectedBundle:String=lineBundle,autoFriend:Bool=true,friendAttempted:Bool=false)->ScreenDecision{
        guard screen.bundle==expectedBundle else{return .pause("已離開 LINE 或出現系統畫面。")}
        if screen.nodes.contains(where:{$0.type=="XCUIElementTypeAlert"}){return .pause("畫面顯示對話框，請處理後恢復。")}
        let texts=screen.nodes.flatMap(\.labels).map(normalize)
        func has(_ labels:[String])->Bool{labels.contains{texts.contains(normalize($0))}}
        let coupon=has(couponHeaders) || !matches(screen,actions+["查看已領取的優惠券","已結束"],disabled:true).isEmpty
        if coupon {
            if !matches(screen,["已結束"],disabled:true).isEmpty{return .terminal("ENDED")}
            if !matches(screen,claimed,disabled:true).isEmpty || has(participated){return .terminal("ALREADY")}
            if has(completed) || !matches(screen,["可惜...沒有抽中！"],disabled:true).isEmpty{return .terminal("COMPLETE")}
        }
        if texts.contains(where:{text in blockers.contains{text.lowercased().contains(normalize($0))}}){return .pause("需要登入、驗證或其他人工處理。")}
        let candidates=matches(screen,actions)
        if candidates.count>1{return .pause("底部有多個操作目標，請確認畫面。")}
        func action(_ n:ScreenNode)->ScreenDecision{
            let label=n.labels.map(normalize).first{actions.map(normalize).contains($0)} ?? ""
            let kind=combined.map(normalize).contains(label) ? "ADD_FRIEND_AND_SUBMIT":label==normalize("加入好友") ? "ADD_FRIEND":"SUBMIT"
            if kind.contains("FRIEND") && !autoFriend{return .pause("需要加入好友，請開啟自動加入好友。")}
            if kind=="ADD_FRIEND" && friendAttempted{return .wait};return .click(kind,n)
        }
        if let n=candidates.first{return action(n)}
        let friends=matches(screen,["加入好友"],bottom:false).filter{$0.type=="XCUIElementTypeButton"}
        if !friendAttempted && friends.count==1 && has(["官方帳號","官方帳號優惠券"]){return action(friends[0])}
        if friendAttempted && has(["已加入好友","聊天"]){return .reopen}
        return .wait
    }
    public static func closeTarget(_ s:DeviceScreen)->ScreenNode?{
        guard s.nodes.flatMap(\.labels).map(normalize).contains(where:{couponHeaders.contains($0)}) else{return nil}
        let list=matches(s,["關閉","Close","关闭"],bottom:false).filter{$0.type=="XCUIElementTypeButton" && $0.rect.y<s.height*0.22}
        return list.count==1 ? list[0]:nil
    }
    public static func parse(_ xml:String)throws->[ScreenNode]{
        guard xml.utf8.count<8_000_000,!xml.uppercased().contains("<!DOCTYPE"),!xml.uppercased().contains("<!ENTITY"),let bytes=xml.data(using:.utf8) else{throw LineDrawError.message("畫面資料不合法。")}
        let delegate=ScreenParser();let parser=XMLParser(data:bytes);parser.shouldResolveExternalEntities=false;parser.delegate=delegate
        guard parser.parse() else{throw LineDrawError.message("畫面資料無法解析。")};return delegate.nodes
    }
}
private final class ScreenParser:NSObject,XMLParserDelegate{
    var nodes=[ScreenNode]();var stack=[(visible:Bool,web:ScreenRect?)]()
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]){
        let parent=stack.last ?? (true,nil);let visible=parent.visible && a["visible"] != "false" && name != "XCUIElementTypeStatusBar"
        let r=ScreenRect(x:Double(a["x"] ?? "") ?? 0,y:Double(a["y"] ?? "") ?? 0,width:Double(a["width"] ?? "") ?? 0,height:Double(a["height"] ?? "") ?? 0)
        let labels=["label","name","value"].compactMap{a[$0]}.filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.reduce(into:[String]()){if !$0.contains($1){$0.append($1)}}
        if visible && name.hasPrefix("XCUIElementType"){nodes.append(ScreenNode(type:a["type"] ?? name,labels:labels,rect:r,enabled:a["enabled"] != "false"))}
        let web=name=="XCUIElementTypeWebView" && visible ? r:parent.web
        let wrapper=parent.visible && name=="XCUIElementTypeOther" && a["visible"]=="false" && a["accessible"]=="false" && labels.isEmpty && web != nil && r==web && r.width>0
        stack.append((visible || wrapper,web))
    }
    func parser(_ parser:XMLParser,didEndElement:String,namespaceURI:String?,qualifiedName:String?){if !stack.isEmpty{stack.removeLast()}}
}
