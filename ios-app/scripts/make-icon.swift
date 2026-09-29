import AppKit
let size=NSSize(width:1024,height:1024)
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let bg=NSBezierPath(rect:NSRect(origin:.zero,size:size));NSGradient(starting:NSColor(calibratedRed:0.20,green:0.52,blue:0.98,alpha:1),ending:NSColor(calibratedRed:0.24,green:0.21,blue:0.65,alpha:1))!.draw(in:bg,angle:-60)
NSColor.white.withAlphaComponent(0.16).setFill();NSBezierPath(ovalIn:NSRect(x:-200,y:490,width:1100,height:1000)).fill()
NSGraphicsContext.saveGraphicsState();let transform=AffineTransform(translationByX:512,byY:512);var rotation=AffineTransform(rotationByDegrees:15);var t=transform;t.append(rotation);t.translate(x:-512,y:-512);(t as NSAffineTransform).concat()
let card=NSBezierPath(roundedRect:NSRect(x:198,y:305,width:628,height:414),xRadius:68,yRadius:68)
NSColor.white.withAlphaComponent(0.92).setFill();card.fill()
NSColor(calibratedRed:0.27,green:0.46,blue:0.87,alpha:1).setStroke();let line=NSBezierPath();line.move(to:NSPoint(x:400,y:357));line.line(to:NSPoint(x:400,y:667));line.lineWidth=9;line.setLineDash([16,16],count:2,phase:0);line.stroke()
let tick=NSBezierPath();tick.move(to:NSPoint(x:474,y:510));tick.line(to:NSPoint(x:548,y:438));tick.line(to:NSPoint(x:704,y:594));tick.lineWidth=35;tick.lineCapStyle = .round;tick.lineJoinStyle = .round;tick.stroke();NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState();try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
