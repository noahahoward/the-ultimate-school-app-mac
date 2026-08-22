import AppKit
import Foundation

// Renders Locker's app icon: the day spine in miniature — class blocks stacked
// on a rail, crossed by the highlighter line that marks "now".

func color(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

let background = color("1B2030")
let rail = color("39415A")
let highlighter = color("FFD84D")
let blocks = [color("4D96FF"), color("6BCB77"), color("EC6FB0")]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let unit = size / 1024
    let inset = 84 * unit
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    let squircle = NSBezierPath(roundedRect: body, xRadius: 200 * unit, yRadius: 200 * unit)
    background.setFill()
    squircle.fill()

    // The rail.
    let railX = body.minX + 150 * unit
    let railWidth = 26 * unit
    let railPath = NSBezierPath(
        roundedRect: NSRect(x: railX, y: body.minY + 130 * unit, width: railWidth, height: body.height - 260 * unit),
        xRadius: railWidth / 2, yRadius: railWidth / 2
    )
    rail.setFill()
    railPath.fill()

    // Class blocks hanging off the rail, drawn top to bottom.
    let blockHeights: [CGFloat] = [150, 190, 130]
    var cursorY = body.maxY - 150 * unit
    for (index, height) in blockHeights.enumerated() {
        let blockHeight = height * unit
        cursorY -= blockHeight
        let bar = NSBezierPath(
            roundedRect: NSRect(x: railX, y: cursorY, width: railWidth, height: blockHeight),
            xRadius: railWidth / 2, yRadius: railWidth / 2
        )
        blocks[index].setFill()
        bar.fill()

        let lineWidth = [330, 250, 300][index] * unit
        let line = NSBezierPath(
            roundedRect: NSRect(
                x: railX + 80 * unit,
                y: cursorY + blockHeight / 2 - 22 * unit,
                width: lineWidth, height: 44 * unit
            ),
            xRadius: 22 * unit, yRadius: 22 * unit
        )
        blocks[index].withAlphaComponent(0.42).setFill()
        line.fill()

        cursorY -= 60 * unit
    }

    // The "now" line.
    let nowY = body.minY + 300 * unit
    let nowLine = NSBezierPath(
        roundedRect: NSRect(x: body.minX + 90 * unit, y: nowY, width: body.width - 180 * unit, height: 18 * unit),
        xRadius: 9 * unit, yRadius: 9 * unit
    )
    highlighter.setFill()
    nowLine.fill()

    let knob = NSBezierPath(ovalIn: NSRect(
        x: railX + railWidth / 2 - 40 * unit, y: nowY + 9 * unit - 40 * unit,
        width: 80 * unit, height: 80 * unit
    ))
    highlighter.setFill()
    knob.fill()

    return image
}

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Locker/Resources/Assets.xcassets/AppIcon.appiconset"

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("failed at \(size)")
        exit(1)
    }
    let url = URL(fileURLWithPath: "\(outputDirectory)/icon_\(size).png")
    try png.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
