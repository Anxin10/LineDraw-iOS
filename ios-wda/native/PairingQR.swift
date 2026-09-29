import Foundation
import CoreImage
import AppKit
let filter=CIFilter(name:"CIQRCodeGenerator")!
filter.setValue(Data(CommandLine.arguments[1].utf8),forKey:"inputMessage")
filter.setValue("M",forKey:"inputCorrectionLevel")
let image=filter.outputImage!.transformed(by:CGAffineTransform(scaleX:8,y:8))
let data=CIContext().pngRepresentation(of:image,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())!
print(data.base64EncodedString())
