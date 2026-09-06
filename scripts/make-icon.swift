import AppKit
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.07, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210).fill()
let accent = NSColor(calibratedRed: 0.32, green: 0.94, blue: 0.91, alpha: 1)
for radius in [310.0, 390.0] {
    accent.withAlphaComponent(0.22).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2)); ring.lineWidth = 5; ring.stroke()
}
let hex = NSBezierPath()
for i in 0..<6 {
    let angle = Double(i) * .pi / 3 + .pi / 2
    let point = NSPoint(x: 512 + cos(angle)*262, y: 512 + sin(angle)*285)
    if i == 0 { hex.move(to: point) } else { hex.line(to: point) }
}
hex.close(); accent.withAlphaComponent(0.1).setFill(); hex.fill(); accent.setStroke(); hex.lineWidth = 10; hex.stroke()
accent.setFill()
NSBezierPath(roundedRect: NSRect(x: 372, y: 422, width: 280, height: 180), xRadius: 24, yRadius: 24).fill()
NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.07, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 401, y: 451, width: 167, height: 13), xRadius: 6, yRadius: 6).fill()
NSBezierPath(ovalIn: NSRect(x: 602, y: 451, width: 14, height: 14)).fill()
accent.setFill(); NSBezierPath(ovalIn: NSRect(x: 784, y: 716, width: 30, height: 30)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
// ic10 is the 1024px PNG representation in an ICNS container.
var data = Data("icns".utf8)
func appendUInt(_ value: UInt32, to data: inout Data) { var big = value.bigEndian; withUnsafeBytes(of: &big) { data.append(contentsOf: $0) } }
appendUInt(UInt32(16 + png.count), to: &data)
data.append(Data("ic10".utf8)); appendUInt(UInt32(8 + png.count), to: &data); data.append(png)
try data.write(to: URL(fileURLWithPath: destination))
