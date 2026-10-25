import AppKit
let directory = CommandLine.arguments[1]
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size*scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        let rect = NSRect(x:0,y:0,width:pixels,height:pixels)
        NSColor(calibratedRed:0.12,green:0.25,blue:0.52,alpha:1).setFill()
        NSBezierPath(roundedRect:rect.insetBy(dx:Double(pixels)*0.04,dy:Double(pixels)*0.04),xRadius:Double(pixels)*0.22,yRadius:Double(pixels)*0.22).fill()
        if let symbol = NSImage(systemSymbolName:"hand.draw.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:Double(pixels)*0.55,weight:.medium)) {
            let s = symbol.size, factor = min(Double(pixels)*0.6/s.width,Double(pixels)*0.65/s.height)
            let target = NSRect(x:(Double(pixels)-s.width*factor)/2,y:(Double(pixels)-s.height*factor)/2,width:s.width*factor,height:s.height*factor)
            NSColor.white.set(); symbol.draw(in:target)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using:.png,properties:[:]) else { fatalError("Icon rendering failed") }
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to:URL(fileURLWithPath:directory).appendingPathComponent(filename))
    }
}
// ICNS supports PNG payloads directly. Assemble deterministic icon chunks without
// depending on iconutil's image conversion service being available in CI.
func be(_ n: Int) -> Data { var v = UInt32(n).bigEndian; return Data(bytes:&v,count:4) }
var chunks = Data()
for (tag, name) in [("icp4","icon_16x16.png"),("icp5","icon_32x32.png"),("icp6","icon_32x32@2x.png"),("ic07","icon_128x128.png"),("ic08","icon_256x256.png"),("ic09","icon_512x512.png"),("ic10","icon_512x512@2x.png"),("ic11","icon_16x16@2x.png"),("ic12","icon_32x32@2x.png"),("ic13","icon_128x128@2x.png"),("ic14","icon_256x256@2x.png")] {
    let png = try Data(contentsOf:URL(fileURLWithPath:directory).appendingPathComponent(name))
    chunks.append(Data(tag.utf8)); chunks.append(be(png.count+8)); chunks.append(png)
}
var icon = Data("icns".utf8); icon.append(be(chunks.count+8)); icon.append(chunks)
try icon.write(to:URL(fileURLWithPath:"Resources/AppIcon.icns"))
