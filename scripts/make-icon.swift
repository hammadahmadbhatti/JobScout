// Renders the JobScout app icon (magnifier over a briefcase) to icon.png.
// Run: swift scripts/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background: rounded rect with vertical gradient (deep blue → teal).
let inset: CGFloat = 64
let bgRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = CGPath(roundedRect: bgRect, cornerWidth: 180, cornerHeight: 180, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [
    CGColor(red: 0.07, green: 0.23, blue: 0.49, alpha: 1),
    CGColor(red: 0.06, green: 0.55, blue: 0.60, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size - inset),
    end: CGPoint(x: size / 2, y: inset),
    options: [])

// Briefcase body.
ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.92))
let caseRect = CGRect(x: 250, y: 300, width: 524, height: 330)
ctx.addPath(CGPath(roundedRect: caseRect, cornerWidth: 46, cornerHeight: 46, transform: nil))
ctx.fillPath()
// Handle.
ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.92))
ctx.setLineWidth(40)
let handle = CGMutablePath()
handle.move(to: CGPoint(x: 420, y: 630))
handle.addLine(to: CGPoint(x: 420, y: 672))
handle.addArc(
    tangent1End: CGPoint(x: 420, y: 700), tangent2End: CGPoint(x: 460, y: 700), radius: 28)
handle.addLine(to: CGPoint(x: 564, y: 700))
handle.addArc(
    tangent1End: CGPoint(x: 604, y: 700), tangent2End: CGPoint(x: 604, y: 672), radius: 28)
handle.addLine(to: CGPoint(x: 604, y: 630))
ctx.addPath(handle)
ctx.strokePath()
// Case latch line.
ctx.setFillColor(CGColor(red: 0.06, green: 0.35, blue: 0.50, alpha: 0.35))
ctx.fill(CGRect(x: 250, y: 445, width: 524, height: 22))

// Magnifier (over the case, bottom-right).
let lensCenter = CGPoint(x: 620, y: 400)
let lensRadius: CGFloat = 150
ctx.setFillColor(CGColor(red: 0.99, green: 0.79, blue: 0.21, alpha: 1))
// Handle of the magnifier.
ctx.saveGState()
ctx.translateBy(x: lensCenter.x, y: lensCenter.y)
ctx.rotate(by: -.pi / 4)
ctx.addPath(
    CGPath(
        roundedRect: CGRect(x: lensRadius - 8, y: -34, width: 210, height: 68),
        cornerWidth: 34, cornerHeight: 34, transform: nil))
ctx.fillPath()
ctx.restoreGState()
// Lens ring.
ctx.setStrokeColor(CGColor(red: 0.99, green: 0.79, blue: 0.21, alpha: 1))
ctx.setLineWidth(58)
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
    width: lensRadius * 2, height: lensRadius * 2))
ctx.strokePath()
// Lens glass.
ctx.setFillColor(CGColor(red: 0.75, green: 0.93, blue: 0.96, alpha: 0.55))
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius + 29, y: lensCenter.y - lensRadius + 29,
    width: (lensRadius - 29) * 2, height: (lensRadius - 29) * 2))
ctx.fillPath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
