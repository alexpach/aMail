// Rasterize an SVG to PNG at a given pixel size. Usage: render-svg <in.svg> <out.png> <px> [<px-height>]
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let px = Int(args[3]) else {
    FileHandle.standardError.write("usage: render-svg <in.svg> <out.png> <px> [px-height]\n".data(using: .utf8)!)
    exit(2)
}
let pxH = args.count >= 5 ? (Int(args[4]) ?? px) : px
guard let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("cannot load \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: pxH, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: px, height: pxH),
           from: .zero, operation: .copy, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: args[2]))
