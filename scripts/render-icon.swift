// Renderiza em PNG, com o motor nativo do macOS, um SVG ou o ícone de um .app (do jeito que o
// sistema o desenha, com o Liquid Glass aplicado). Uso: render-icon in.svg|in.app tamanho out.png
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let size = Int(args[2]) else { fatalError("uso: render-icon in.svg|in.app tamanho out.png") }
let image = args[1].hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: args[1]) : NSImage(contentsOfFile: args[1])
guard let image else { fatalError("não consegui abrir \(args[1])") }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
