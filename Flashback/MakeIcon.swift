// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
@main struct IconMaker {
    static func main() throws {
        let icon = NSImage(size:NSSize(width:1024,height:1024))
        icon.lockFocus()
        let tile = NSBezierPath(roundedRect:NSRect(x:96,y:96,width:832,height:832),xRadius:185,yRadius:185)
        NSGradient(colors:[NSColor(srgbRed:0.99,green:0.49,blue:0.22,alpha:1),
                           NSColor(srgbRed:0.90,green:0.24,blue:0.13,alpha:1)])!.draw(in:tile,angle:-90)
        BrandArtwork.draw(in:NSRect(x:178,y:182,width:660,height:660),
                          color:NSColor(srgbRed:1,green:0.97,blue:0.89,alpha:1))
        icon.unlockFocus()
        let rep = NSBitmapImageRep(data:icon.tiffRepresentation!)!
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
