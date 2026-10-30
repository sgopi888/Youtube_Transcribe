// Usage: swift Icon/make_icon.swift Icon/source.png Icon/master.png
// Cuts the rounded tile out of the 1024 px design render (stitch_ytscribe_macos_suite (1)/screen.png)
// and places it on the macOS icon grid with a transparent background.
import AppKit

let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
let size: CGFloat = 1024
// The tile in the render spans x/y 193...833 (measured); trim 4 px so the grey backdrop never shows.
let tile = NSRect(x: 197, y: 197, width: 632, height: 632)

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
// macOS icon grid: 824 pt squircle centred in the 1024 canvas.
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 150, yRadius: 150)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()
shape.addClip()
src.draw(in: rect, from: tile, operation: .copy, fraction: 1)
img.unlockFocus()

let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
