// Render the project's SF Symbol as a square PNG. Usage: render-symbol <out.png> <px>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let px = Int(args[2]), px > 0 else {
    FileHandle.standardError.write(Data("usage: render-symbol <out.png> <px>\n".utf8))
    exit(2)
}
let symbolName = "envelope.open.fill"
let config = NSImage.SymbolConfiguration(pointSize: 700, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "aMail")?
    .withSymbolConfiguration(config),
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let side = CGFloat(px)
let inset = side * 0.045
NSColor(srgbRed: 0.125, green: 0.36, blue: 0.69, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset),
    xRadius: side * 0.2, yRadius: side * 0.2).fill()
let scale = side * 0.65 / max(symbol.size.width, symbol.size.height)
let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
symbol.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
    width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: args[1]))
