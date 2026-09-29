import Foundation
import CoreGraphics

public enum DeviceElementLookupError:Error {case incompleteResponse, invalidGeometry}

/// Read-only WDA lookup; no element identifiers are retained across navigations.
/// Native predicate queries avoid serializing the entire XML hierarchy, but
/// still require an XCTest snapshot. Performance must be measured on the phone.
public enum DeviceElementLookup {
    public static let responseAttributes="type,label,attribute/name,attribute/value,rect,enabled,displayed"
    public static let bottomRegion=CGRect(x:0,y:0,width:1,height:0.4)

    public static let predicate:String = {
        // Only relevant labels: enumerating all buttons also resolves stale
        // controls in LINE's underlying chat while the coupon sheet appears.
        // Disabled result labels and non-button text remain included.
        // Whitespace and ASCII width variants must not hide a blocking prompt.
        let terms=Array(Set((DeviceScreenRules.observationLabels+DeviceScreenRules.blockers).map(DeviceScreenRules.normalize))).sorted()
        let alternatives=terms.map { term in
            term.unicodeScalars.map { scalar->String in
                let plain=NSRegularExpression.escapedPattern(for:String(scalar))
                if scalar.value>=0x21,scalar.value<=0x7e,let wide=UnicodeScalar(scalar.value+0xfee0) {
                    return "(?:"+plain+"|"+NSRegularExpression.escapedPattern(for:String(wide))+")"
                }
                return plain
            }.joined(separator:"\\s*")
        }.joined(separator:"|")
        let pattern="(?s).*(?:"+alternatives+").*"
        let quoted="'"+pattern.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"'",with:"\\'")+"'"
        let text=["label","name","value"].map{"\($0) MATCHES[c] \(quoted)"}.joined(separator:" OR ")
        return "type IN {'XCUIElementTypeApplication','XCUIElementTypeAlert'} OR (\(text))"
    }()

    public static func screen(from value:Any,bundle:String)throws->DeviceScreen {
        guard let rows=value as? [[String:Any]],!rows.isEmpty,rows.count<=512 else{throw DeviceElementLookupError.incompleteResponse}
        var nodes=[ScreenNode]()
        for row in rows {
            guard let type=row["type"] as? String,type.hasPrefix("XCUIElementType"),
                  let rect=row["rect"] as? [String:Any],
                  let x=rect["x"] as? Double,let y=rect["y"] as? Double,
                  let width=rect["width"] as? Double,let height=rect["height"] as? Double,
                  [x,y,width,height].allSatisfy(\.isFinite),width>=0,height>=0,
                  let enabled=row["enabled"] as? Bool,let displayed=row["displayed"] as? Bool,
                  row.keys.contains("label")
            else{throw DeviceElementLookupError.incompleteResponse}
            // WDA versions may omit nil arbitrary attributes instead of
            // serializing null. Rect/enabled/displayed remain mandatory.
            for key in ["label","attribute/name","attribute/value"] {
                if let field=row[key],!(field is String),!(field is NSNull){throw DeviceElementLookupError.incompleteResponse}
            }
            guard displayed || type=="XCUIElementTypeApplication" else{continue}
            let labels=["label","attribute/name","attribute/value"].compactMap{row[$0] as? String}
                .filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
                .reduce(into:[String]()){if !$0.contains($1){$0.append($1)}}
            nodes.append(.init(type:type,labels:labels,rect:.init(x:x,y:y,width:width,height:height),enabled:enabled))
        }
        let apps=nodes.filter{$0.type=="XCUIElementTypeApplication"}
        // Do not guess dimensions from a previous phone, orientation or screenshot.
        guard apps.count==1,let frame=apps.first?.rect,frame.x==0,frame.y==0,
              frame.width>0,frame.height>0 else{throw DeviceElementLookupError.invalidGeometry}
        return DeviceScreen(bundle:bundle,width:frame.width,height:frame.height,nodes:nodes,targeted:true)
    }
}

/// Native find-elements is not uniformly faster than source retrieval. Compare
/// successful, classified observations only and avoid repeatedly paying for a
/// slower path on the same device/session. UI loading/foreground/OCR time is not
/// part of either sample. A margin prevents switching on insignificant jitter.
public struct DeviceLookupBudget:Sendable {
    private var full=[Double]();private var targeted=[Double]()
    public private(set) var failed=false
    public init(){}
    public mutating func recordFailure(){failed=true}
    public mutating func recordFull(_ seconds:Double){guard seconds.isFinite,seconds>0 else{return};full.append(seconds);full=Array(full.suffix(3))}
    public mutating func recordTargeted(_ seconds:Double){guard seconds.isFinite,seconds>0 else{return};targeted.append(seconds);targeted=Array(targeted.suffix(3))}
    public var preferFull:Bool {
        if failed{return true}
        guard full.count>=2,targeted.count>=2 else{return false}
        let a=full.reduce(0,+)/Double(full.count),b=targeted.reduce(0,+)/Double(targeted.count)
        return b>a*1.25+0.05
    }
}
