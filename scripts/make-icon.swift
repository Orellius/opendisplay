// Renders assets/AppIcon.icns from the OpenDisplay mark.
//
// The mark is the one in assets/logo.svg: a dark tile holding a display frame with a
// 2x2 pixel grid, one of them orange - one point becoming four pixels, which is what
// HiDPI is. This file redraws it rather than rasterizing the SVG for one reason: the
// macOS app-icon silhouette is a squircle (superellipse), not the circular-corner
// rounded rect an SVG `rx` produces, and the difference is visible at 512pt and up.
//
// Geometry follows Apple's icon grid: a 1024 canvas with an 824 body inset 100 on all
// sides, so the icon lines up optically with every system icon beside it in Finder.
//
// Run: swift scripts/make-icon.swift    (writes assets/AppIcon.icns)
// Only needed when the mark changes; the .icns is committed.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark, in 1024-canvas units

let canvas: CGFloat = 1024
let bodyInset: CGFloat = 100          // Apple icon grid: 824 body inside a 1024 canvas
let bodySide: CGFloat = canvas - bodyInset * 2

let frameInset: CGFloat = 128         // display frame, measured from the body edge
let frameStroke: CGFloat = 22
let frameRadius: CGFloat = 84
let pixelPad: CGFloat = 56            // frame inner edge to the pixel block
let pixelGap: CGFloat = 32
let pixelRadius: CGFloat = 50

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let tileTop = rgb(0x1B, 0x1E, 0x23)
let tileBottom = rgb(0x0E, 0x10, 0x13)
let frameColor = rgb(0x3A, 0x3F, 0x47)
let pixelColor = rgb(0xE8, 0xE6, 0xE1)
let accentColor = rgb(0xFF, 0x6A, 0x00)

// MARK: - Paths

/// Apple's icon silhouette. A square superellipse (|x|^n + |y|^n = 1, n ~ 5) rather than
/// a circular-corner rounded rect; sampled densely enough that the curve is smooth at 1024.
func squirclePath(in rect: CGRect, exponent n: CGFloat = 5, samples: Int = 2048) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let rx = rect.width / 2, ry = rect.height / 2
    let e = 2 / n
    for i in 0..<samples {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
        let c = cos(t), s = sin(t)
        let x = cx + rx * (c < 0 ? -1 : 1) * pow(abs(c), e)
        let y = cy + ry * (s < 0 ? -1 : 1) * pow(abs(s), e)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Render

func drawIcon(size: CGFloat) -> CGImage {
    let px = Int(size)
    let scale = size / canvas
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("could not create a \(px)x\(px) context") }

    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let body = CGRect(x: bodyInset, y: bodyInset, width: bodySide, height: bodySide)
    let bodyPath = squirclePath(in: body)

    // Drop shadow, so the tile sits at the same depth as the system icons next to it.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 46, color: rgb(0, 0, 0, 0.30))
    ctx.addPath(bodyPath)
    ctx.setFillColor(tileBottom)
    ctx.fillPath()
    ctx.restoreGState()

    // Tile gradient, clipped to the silhouette. CG's origin is bottom-left, so the
    // gradient runs from the bottom stop up to the top one.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [tileBottom, tileTop] as CFArray, locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY),
        options: []
    )
    ctx.restoreGState()

    // A hairline lift on the edge, so the dark tile still reads as an object on a dark Dock.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.08))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // The display frame.
    let frame = body.insetBy(dx: frameInset, dy: frameInset)
    ctx.addPath(roundedPath(frame.insetBy(dx: frameStroke / 2, dy: frameStroke / 2), frameRadius))
    ctx.setStrokeColor(frameColor)
    ctx.setLineWidth(frameStroke)
    ctx.strokePath()

    // Four pixels inside it; the bottom-right one carries the accent.
    let grid = frame.insetBy(dx: pixelPad, dy: pixelPad)
    let cell = (grid.width - pixelGap) / 2
    for (col, row) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let rect = CGRect(
            x: grid.minX + CGFloat(col) * (cell + pixelGap),
            y: grid.minY + CGFloat(row) * (cell + pixelGap),
            width: cell, height: cell
        )
        // Row 0 is the bottom row in CG coordinates, so the accent is (col 1, row 0).
        ctx.setFillColor(col == 1 && row == 0 ? accentColor : pixelColor)
        ctx.addPath(roundedPath(rect, pixelRadius))
        ctx.fillPath()
    }

    guard let image = ctx.makeImage() else { fatalError("could not render at \(px)x\(px)") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not finalize \(url.path)") }
}

// MARK: - Emit the iconset and hand it to iconutil

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) -> the filenames iconutil expects.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in variants {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    writePNG(drawIcon(size: CGFloat(points * scale)), to: iconset.appendingPathComponent(name))
}

let icns = root.appendingPathComponent("assets/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

print("wrote \(icns.path)")
