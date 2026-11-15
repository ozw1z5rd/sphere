// Draws the Sphere app icon: a round brain in green and electric blue with a
// circuit-board feel. Usage: swift scripts/draw-icon.swift <output.png>
import Foundation
import CoreGraphics
import ImageIO

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("Could not create bitmap context\n".utf8))
    exit(1)
}

let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let backgroundRect = canvas.insetBy(dx: 44, dy: 44)
let cornerRadius: CGFloat = 208

// Background: dark navy rounded square with a subtle vertical gradient.
let backgroundPath = CGPath(
    roundedRect: backgroundRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
context.saveGState()
context.addPath(backgroundPath)
context.clip()
let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.055, green: 0.085, blue: 0.16, alpha: 1),
        CGColor(red: 0.015, green: 0.025, blue: 0.06, alpha: 1),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: canvas.midX, y: canvas.maxY),
    end: CGPoint(x: canvas.midX, y: canvas.minY),
    options: []
)

// Faint circuit grid in the background.
context.setStrokeColor(CGColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 0.07))
context.setLineWidth(2)
var gridX: CGFloat = 120
while gridX < 960 {
    context.move(to: CGPoint(x: gridX, y: 80))
    context.addLine(to: CGPoint(x: gridX, y: 944))
    gridX += 84
}
var gridY: CGFloat = 120
while gridY < 960 {
    context.move(to: CGPoint(x: 80, y: gridY))
    context.addLine(to: CGPoint(x: 944, y: gridY))
    gridY += 84
}
context.strokePath()

context.setFillColor(CGColor(red: 0.25, green: 0.75, blue: 1.0, alpha: 0.14))
for x in stride(from: 120.0, through: 960.0, by: 84.0) {
    for y in stride(from: 120.0, through: 960.0, by: 84.0) {
        context.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
    }
}
context.restoreGState()

// Border.
context.addPath(backgroundPath)
context.setStrokeColor(CGColor(red: 0.35, green: 0.6, blue: 1.0, alpha: 0.35))
context.setLineWidth(5)
context.strokePath()

let center = CGPoint(x: canvas.midX, y: canvas.midY)
let brainRadius: CGFloat = 318
let brainRect = CGRect(
    x: center.x - brainRadius,
    y: center.y - brainRadius,
    width: brainRadius * 2,
    height: brainRadius * 2
)

// Soft glow behind the brain.
let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.40),
        CGColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.0),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.saveGState()
context.drawRadialGradient(
    glow,
    startCenter: center,
    startRadius: brainRadius * 0.7,
    endCenter: center,
    endRadius: brainRadius * 1.25,
    options: []
)
context.restoreGState()

// Brain body: green -> electric blue gradient clipped to a circle.
context.saveGState()
context.addEllipse(in: brainRect)
context.clip()
let brainGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.16, green: 0.95, blue: 0.60, alpha: 1),
        CGColor(red: 0.10, green: 0.62, blue: 0.95, alpha: 1),
        CGColor(red: 0.12, green: 0.30, blue: 1.0, alpha: 1),
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
context.drawLinearGradient(
    brainGradient,
    start: CGPoint(x: brainRect.minX, y: brainRect.minY),
    end: CGPoint(x: brainRect.maxX, y: brainRect.maxY),
    options: []
)

// Slightly darken the rim for depth.
let rim = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        CGColor(red: 0.0, green: 0.02, blue: 0.10, alpha: 0.45),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawRadialGradient(
    rim,
    startCenter: center,
    startRadius: brainRadius * 0.55,
    endCenter: center,
    endRadius: brainRadius,
    options: []
)

// Central sulcus (wavy vertical line).
let sulcus = CGMutablePath()
sulcus.move(to: CGPoint(x: center.x, y: brainRect.maxY - 12))
sulcus.addCurve(
    to: CGPoint(x: center.x + 18, y: center.y + 90),
    control1: CGPoint(x: center.x - 60, y: center.y + 210),
    control2: CGPoint(x: center.x + 70, y: center.y + 160)
)
sulcus.addCurve(
    to: CGPoint(x: center.x - 12, y: center.y - 90),
    control1: CGPoint(x: center.x - 40, y: center.y + 30),
    control2: CGPoint(x: center.x + 40, y: center.y - 20)
)
sulcus.addCurve(
    to: CGPoint(x: center.x, y: brainRect.minY + 12),
    control1: CGPoint(x: center.x - 50, y: center.y - 180),
    control2: CGPoint(x: center.x + 40, y: center.y - 240)
)
context.addPath(sulcus)
context.setStrokeColor(CGColor(red: 0.03, green: 0.10, blue: 0.22, alpha: 0.55))
context.setLineWidth(22)
context.setLineCap(.round)
context.strokePath()

// Brain folds (gyri) as arcs on both hemispheres.
func fold(_ c: CGPoint, _ r: CGFloat, _ start: CGFloat, _ end: CGFloat, width: CGFloat) {
    context.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.20))
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.strokePath()
}

let left = CGPoint(x: center.x - 150, y: center.y + 20)
let right = CGPoint(x: center.x + 150, y: center.y - 20)
fold(left, 120, 0.55, 2.55, width: 16)
fold(left, 190, 0.65, 2.45, width: 14)
fold(left, 255, 0.80, 2.30, width: 12)
fold(right, 120, 0.60, 2.60, width: 16)
fold(right, 190, 0.70, 2.50, width: 14)
fold(right, 255, 0.85, 2.35, width: 12)

// Circuit traces with terminal pads.
context.setLineCap(.round)
context.setLineJoin(.round)

func trace(_ points: [CGPoint], color: CGColor, width: CGFloat) {
    guard let first = points.first else { return }
    let path = CGMutablePath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokePath()
}

func pad(_ point: CGPoint, color: CGColor, radius: CGFloat) {
    context.setFillColor(color.copy(alpha: 0.28) ?? color)
    context.fillEllipse(in: CGRect(x: point.x - radius * 1.8, y: point.y - radius * 1.8, width: radius * 3.6, height: radius * 3.6))
    context.setFillColor(color)
    context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
}

let cyan = CGColor(red: 0.55, green: 0.98, blue: 1.0, alpha: 0.95)
let lime = CGColor(red: 0.55, green: 1.0, blue: 0.65, alpha: 0.95)

let tracesLeft: [[CGPoint]] = [
    [CGPoint(x: 352, y: 610), CGPoint(x: 300, y: 610), CGPoint(x: 300, y: 690), CGPoint(x: 236, y: 690)],
    [CGPoint(x: 378, y: 470), CGPoint(x: 316, y: 470), CGPoint(x: 316, y: 402), CGPoint(x: 250, y: 402)],
    [CGPoint(x: 404, y: 742), CGPoint(x: 404, y: 806), CGPoint(x: 470, y: 806)],
]
let tracesRight: [[CGPoint]] = [
    [CGPoint(x: 672, y: 560), CGPoint(x: 736, y: 560), CGPoint(x: 736, y: 492), CGPoint(x: 800, y: 492)],
    [CGPoint(x: 648, y: 430), CGPoint(x: 712, y: 430), CGPoint(x: 712, y: 360), CGPoint(x: 776, y: 360)],
    [CGPoint(x: 600, y: 730), CGPoint(x: 600, y: 798), CGPoint(x: 536, y: 798)],
]

for path in tracesLeft {
    trace(path, color: lime, width: 11)
    for point in path { pad(point, color: lime, radius: 9) }
}
for path in tracesRight {
    trace(path, color: cyan, width: 11)
    for point in path { pad(point, color: cyan, radius: 9) }
}

context.restoreGState()

// Outer ring.
context.setStrokeColor(CGColor(red: 0.72, green: 0.98, blue: 1.0, alpha: 0.55))
context.setLineWidth(7)
context.strokeEllipse(in: brainRect.insetBy(dx: 2, dy: 2))

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("Could not render icon\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("Could not create image destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("Could not write PNG\n".utf8))
    exit(1)
}
print(outputPath)
