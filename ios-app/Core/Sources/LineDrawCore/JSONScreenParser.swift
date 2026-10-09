import Foundation

/// Bounded parser for WDA's native tree. Missing state never enables a button.
public enum JSONScreenParser {
    public static func parse(_ data:Data,limits:XMLParseLimits=XMLParseLimits())throws->[ScreenNode]{
        guard data.count<limits.bytes else{throw ObservationFailure.invalidXML}
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw ObservationFailure.invalidXML}
        var result=[ScreenNode](),count=0
        func flag(_ value:Any?)->Bool?{
            if let s=value as? String{return ["true","1"].contains(s.lowercased()) ? true:["false","0"].contains(s.lowercased()) ? false:nil}
            if let n=value as? NSNumber{return n.boolValue};return nil
        }
        func walk(_ node:[String:Any],depth:Int,parentVisible:Bool,web:ScreenRect?)throws{
            try Task.checkCancellation();count+=1
            guard count<=limits.nodes,depth<limits.depth,let raw=node["type"] as? String,
                  let rect=node["rect"] as? [String:Any] else{throw ObservationFailure.invalidXML}
            let values=try ["x","y","width","height"].map{key->Double in
                guard let number=rect[key] as? NSNumber,number.doubleValue.isFinite else{throw ObservationFailure.invalidXML};return number.doubleValue
            }
            guard values[2]>=0,values[3]>=0 else{throw ObservationFailure.invalidXML}
            let r=ScreenRect(x:values[0],y:values[1],width:values[2],height:values[3])
            let type=raw.hasPrefix("XCUIElementType") ? raw:"XCUIElementType"+raw
            let labels=["label","name","value"].compactMap{node[$0] as? String}.filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.reduce(into:[String]()){if !$0.contains($1){$0.append($1)}}
            guard labels.allSatisfy({$0.utf8.count<=limits.attributeBytes}) else{throw ObservationFailure.invalidXML}
            let ownVisible=flag(node["isVisible"]),visible=parentVisible && ownVisible != false && type != "XCUIElementTypeStatusBar"
            if visible {result.append(ScreenNode(type:type,labels:labels,rect:r,enabled:flag(node["isEnabled"])==true && ownVisible==true))}
            let childWeb=type=="XCUIElementTypeWebView" && visible ? r:web
            let wrapper=parentVisible && type=="XCUIElementTypeOther" && ownVisible==false && flag(node["isAccessible"])==false && labels.isEmpty && web==r && r.width>0
            if let children=node["children"] {
                guard let children=children as? [[String:Any]] else{throw ObservationFailure.invalidXML}
                for child in children{try walk(child,depth:depth+1,parentVisible:visible || wrapper,web:childWeb)}
            }
        }
        try walk(root,depth:0,parentVisible:true,web:nil)
        return result
    }
}
