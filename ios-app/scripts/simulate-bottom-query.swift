import Foundation
import CoreGraphics
import ImageIO
import Vision

// Offline benchmark only. It does not connect to WDA or dispatch any taps.
let input=CommandLine.arguments[1]
let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:input) as CFURL,nil)!
let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
let width=image.width,height=image.height
var rgba=[UInt8](repeating:0,count:width*height*4)
let decodeStart=CFAbsoluteTimeGetCurrent()
rgba.withUnsafeMutableBytes { bytes in
    let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
}
let decodeSeconds=CFAbsoluteTimeGetCurrent()-decodeStart
func blueBand(_ data:[UInt8],_ w:Int,_ h:Int)->Bool {
    var consecutive=0
    for y in Int(Double(h)*0.75)..<h {
        var blue=0,samples=0
        for x in stride(from:0,to:w,by:4) {
            let offset=(y*w+x)*4,r=Int(data[offset]),g=Int(data[offset+1]),b=Int(data[offset+2])
            if b>150 && b>r+50 && b>g+25 {blue+=1}
            samples+=1
        }
        consecutive=Double(blue)/Double(samples)>0.7 ? consecutive+1:0
        if consecutive>=max(3,h/100) {return true}
    }
    return false
}
let scanStart=CFAbsoluteTimeGetCurrent()
var detected=false
for _ in 0..<100 {detected=blueBand(rgba,width,height)}
let scanSeconds=(CFAbsoluteTimeGetCurrent()-scanStart)/100
let ocrStart=CFAbsoluteTimeGetCurrent()
let request=VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages=["zh-Hant","en-US"]
request.regionOfInterest=CGRect(x:0,y:0,width:1,height:0.25)
try VNImageRequestHandler(cgImage:image).perform([request])
let ocrSeconds=CFAbsoluteTimeGetCurrent()-ocrStart
let words=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}
// Synthetic state checks: a color signal alone cannot identify the text/icon.
let w=400,h=800
func fixture(_ footer:(UInt8,UInt8,UInt8)?)->[UInt8] {
    var data=[UInt8](repeating:255,count:w*h*4)
    if let c=footer {for y in 730..<800 {for x in 0..<w {let i=(y*w+x)*4;data[i]=c.0;data[i+1]=c.1;data[i+2]=c.2}}}
    return data
}
let states:[(String,(UInt8,UInt8,UInt8)?,Bool)]=[
    ("ready-blue",(64,107,239),true),
    ("loading-empty",nil,false),
    ("ended-gray",(170,170,170),false),
    ("result-green",(63,210,125),false)
]
let checks=states.map { state -> [String:Any] in
    let actual=blueBand(fixture(state.1),w,h)
    return ["state":state.0,"detected":actual,"expected":state.2,"passed":actual==state.2]
}
let body:[String:Any]=[
    "kind":"offline-mac-processing-only","width":width,"height":height,
    "decodeSeconds":decodeSeconds,"blueScanSecondsMean100":scanSeconds,
    "blueDetected":detected,"bottomOCRSeconds":ocrSeconds,"recognizedText":words,
    "stateChecks":checks,
    "limits":"No phone screenshot capture, WDA query, icon matching or tap measurement; timings are not iPhone performance."
]
let json=try JSONSerialization.data(withJSONObject:body,options:[.prettyPrinted,.sortedKeys])
print(String(decoding:json,as:UTF8.self))
