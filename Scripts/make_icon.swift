import AppKit
import Foundation
let size=1024
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)
if let bitmap,let graphics=NSGraphicsContext(bitmapImageRep:bitmap) {
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
    let ctx=graphics.cgContext
    ctx.setFillColor(NSColor.black.cgColor);ctx.fill(CGRect(x:0,y:0,width:size,height:size))
    let colors=[NSColor(red:0.04,green:0.065,blue:0.17,alpha:1).cgColor,NSColor.black.cgColor] as CFArray
    if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) { ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:650,y:650),startRadius:20,endCenter:CGPoint(x:512,y:512),endRadius:720,options:[]) }
    let center=CGPoint(x:512,y:520),r=292.0
    ctx.setStrokeColor(NSColor(red:0.5,green:0.46,blue:0.37,alpha:0.45).cgColor);ctx.setLineWidth(2);ctx.strokeEllipse(in:CGRect(x:center.x-r-40,y:center.y-r-40,width:2*r+80,height:2*r+80))
    // Waxing crescent lit right, transparent terminator layered over the void.
    ctx.setFillColor(NSColor(red:0.96,green:0.945,blue:0.9,alpha:1).cgColor)
    let k=0.45
    for i in 0..<1024 { let y = -r+(Double(i)+0.5)*2*r/1024; let limb=sqrt(max(0,r*r-y*y));ctx.fill(CGRect(x:center.x+k*limb,y:center.y+y,width:(1-k)*limb,height:2*r/1024+0.5)) }
    for (x,y,s) in [(220.0,795.0,3.0),(767,233,2),(170,344,1.5),(835,724,2)] { ctx.fillEllipse(in:CGRect(x:x,y:y,width:s,height:s)) }
    NSGraphicsContext.restoreGraphicsState()
    if let png=bitmap.representation(using:.png,properties:[:]) { try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1])) }
}
