import AppKit

// Render the same checkmark identity used by the Flutter navigation rail.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let s = CGFloat(size)
  let face = NSBezierPath(roundedRect: NSRect(x: s * 0.09, y: s * 0.09, width: s * 0.82, height: s * 0.82),
    xRadius: s * 0.19, yRadius: s * 0.19)
  let gradient = NSGradient(starting: NSColor(srgbRed: 0.38, green: 0.35, blue: 0.96, alpha: 1),
    ending: NSColor(srgbRed: 0.27, green: 0.24, blue: 0.85, alpha: 1))!
  gradient.draw(in: face, angle: -90)
  NSColor.white.setStroke()
  let mark = NSBezierPath()
  mark.lineWidth = s * 0.07
  mark.lineCapStyle = .round
  mark.lineJoinStyle = .round
  mark.move(to: NSPoint(x: s * 0.29, y: s * 0.50))
  mark.line(to: NSPoint(x: s * 0.44, y: s * 0.35))
  mark.line(to: NSPoint(x: s * 0.72, y: s * 0.66))
  mark.stroke()
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("app_icon_\(size).png"))
}
