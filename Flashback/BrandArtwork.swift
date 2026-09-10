// SPDX-License-Identifier: GPL-3.0-only
import Cocoa

// Original Flashback artwork: two rewind arrows on a pixel grid.
// Coordinates are authored here; no system symbols or external assets are used.
enum BrandArtwork {
    static func draw(in bounds: NSRect, color: NSColor) {
        let pixel = min(bounds.width,bounds.height) / 14
        let origin = NSPoint(x:bounds.midX - 7 * pixel,y:bounds.midY - 4.5 * pixel)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.shouldAntialias = false
        color.setFill()
        for offset: CGFloat in [1,8] {
            let path = NSBezierPath()
            path.move(to:NSPoint(x:origin.x + (offset + 5) * pixel,y:origin.y))
            for (row, width) in [1,2,3,4,5,4,3,2,1].enumerated() {
                let x = origin.x + (offset + 5 - CGFloat(width)) * pixel
                path.line(to:NSPoint(x:x,y:origin.y + CGFloat(row) * pixel))
                path.line(to:NSPoint(x:x,y:origin.y + CGFloat(row + 1) * pixel))
            }
            path.line(to:NSPoint(x:origin.x + (offset + 5) * pixel,y:origin.y + 9 * pixel))
            path.close(); path.fill()
        }
    }

    static func mark(size: CGFloat) -> NSImage {
        let image = NSImage(size:NSSize(width:size,height:size))
        image.lockFocus()
        draw(in:NSRect(x:0,y:0,width:size,height:size),color:.black)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func wordmark() -> NSImage {
        // Original 5×7 lettering for the fixed brand name, with two-point pixels.
        let letters: [[UInt8]] = [
            [0b11111,0b10000,0b10000,0b11110,0b10000,0b10000,0b10000], // F
            [0b01100,0b00100,0b00100,0b00100,0b00100,0b00100,0b01110], // l
            [0b00000,0b00000,0b01110,0b00001,0b01111,0b10001,0b01111], // a
            [0b00000,0b00000,0b01111,0b10000,0b01110,0b00001,0b11110], // s
            [0b10000,0b10000,0b10110,0b11001,0b10001,0b10001,0b10001], // h
            [0b10000,0b10000,0b10110,0b11001,0b10001,0b10001,0b11110], // b
            [0b00000,0b00000,0b01110,0b00001,0b01111,0b10001,0b01111], // a
            [0b00000,0b00000,0b01111,0b10000,0b10000,0b10000,0b01111], // c
            [0b10000,0b10000,0b10010,0b10100,0b11000,0b10100,0b10010]  // k
        ]
        let image = NSImage(size:NSSize(width:106,height:14))
        image.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = false
        NSColor.black.setFill()
        for (letter, rows) in letters.enumerated() {
            for (row, bits) in rows.enumerated() {
                for column in 0..<5 where bits & (1 << (4-column)) != 0 {
                    NSRect(x:(letter*6+column)*2,y:(6-row)*2,width:2,height:2).fill()
                }
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
