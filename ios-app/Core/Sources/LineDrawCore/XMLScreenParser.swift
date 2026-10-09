import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct XMLParseLimits:Sendable {
    public var bytes=8_000_000,nodes=20_000,depth=64,attributeBytes=65_536
    public init(){}
}
public enum XMLScreenParser {
    public static func parse(_ xml:String,limits:XMLParseLimits=XMLParseLimits(),requireApplication:Bool=true,
                             cancelled:()->Bool={false})throws->[ScreenNode]{
        try Task.checkCancellation()
        guard xml.utf8.count<limits.bytes,!xml.uppercased().contains("<!DOCTYPE"),
              !xml.uppercased().contains("<!ENTITY") else{throw ObservationFailure.invalidXML}
        return try withoutActuallyEscaping(cancelled){check in
            let delegate=XMLNodeParser(limits:limits,cancelled:check)
            let parser=XMLParser(data:Data(xml.utf8));parser.shouldResolveExternalEntities=false;parser.delegate=delegate
            let parsed=parser.parse()
            if cancelled(){throw CancellationError()}
            try Task.checkCancellation()
            guard parsed,!delegate.invalid,delegate.stack.isEmpty else{throw ObservationFailure.invalidXML}
            if requireApplication {
                let apps=delegate.nodes.filter{$0.type=="XCUIElementTypeApplication"}
                guard apps.count==1,let app=apps.first,app.rect.x==0,app.rect.y==0,
                      app.rect.width>0,app.rect.height>0 else{throw ObservationFailure.invalidXML}
            }
            return delegate.nodes
        }
    }
}
private final class XMLNodeParser:NSObject,XMLParserDelegate {
    let limits:XMLParseLimits;let cancelled:()->Bool
    var nodes=[ScreenNode](),stack=[(visible:Bool,web:ScreenRect?)]()
    var count=0,invalid=false
    init(limits:XMLParseLimits,cancelled:@escaping()->Bool){self.limits=limits;self.cancelled=cancelled}
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]) {
        count+=1
        guard !cancelled(),count<=limits.nodes,stack.count<limits.depth,
              a.values.allSatisfy({$0.utf8.count<=limits.attributeBytes}) else{invalid=true;parser.abortParsing();return}
        let parent=stack.last ?? (true,nil)
        let visible=parent.visible && a["visible"] != "false" && name != "XCUIElementTypeStatusBar"
        let values=["x","y","width","height"].map{Double(a[$0] ?? "") ?? 0}
        guard values.allSatisfy(\.isFinite),values[2]>=0,values[3]>=0 else{invalid=true;parser.abortParsing();return}
        let r=ScreenRect(x:values[0],y:values[1],width:values[2],height:values[3])
        let labels=["label","name","value"].compactMap{a[$0]}.filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.reduce(into:[String]()){if !$0.contains($1){$0.append($1)}}
        if visible && name.hasPrefix("XCUIElementType") {
            // Missing state never becomes authorization to tap; result labels remain readable.
            let enabled=a["enabled"]=="true" && a["visible"]=="true" && ["x","y","width","height"].allSatisfy{a[$0] != nil}
            nodes.append(.init(type:a["type"] ?? name,labels:labels,rect:r,enabled:enabled))
        }
        let web=name=="XCUIElementTypeWebView" && visible ? r:parent.web
        let wrapper=parent.visible && name=="XCUIElementTypeOther" && a["visible"]=="false" && a["accessible"]=="false" && labels.isEmpty && web != nil && r==web && r.width>0
        stack.append((visible || wrapper,web))
    }
    func parser(_ parser:XMLParser,didEndElement:String,namespaceURI:String?,qualifiedName:String?){if !stack.isEmpty{stack.removeLast()}}
}
