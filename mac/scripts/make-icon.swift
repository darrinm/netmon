#!/usr/bin/env swift
// Render Netmon's app icon: a blue gradient rounded square with a white
// "antenna.radiowaves.left.and.right" SF Symbol centered on it.
// Produces Netmon/Resources/AppIcon.icns relative to the mac/ directory.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Run from the mac/ directory.
let cwd = FileManager.default.currentDirectoryPath
let outDir = URL(fileURLWithPath: "\(cwd)/Netmon/Resources/AppIcon.iconset")
let icnsURL = URL(fileURLWithPath: "\(cwd)/Netmon/Resources/AppIcon.icns")
try? FileManager.default.removeItem(at: outDir)
try? FileManager.default.removeItem(at: icnsURL)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let symbol = "antenna.radiowaves.left.and.right"

func renderPNG(size: Int) throws {
    let cgSize = CGSize(width: size, height: size)
    let scale: CGFloat = 1

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    // Background gradient (deep blue → cyan-blue)
    let rect = CGRect(origin: .zero, size: cgSize)
    let radius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: cgSize),
                            xRadius: radius, yRadius: radius)
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(red: 0.04, green: 0.20, blue: 0.55, alpha: 1.0),
        NSColor(red: 0.10, green: 0.49, blue: 0.92, alpha: 1.0),
    ])!
    gradient.draw(in: NSRect(origin: .zero, size: cgSize), angle: 90)

    // Subtle inner highlight
    if let top = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.18),
        NSColor.white.withAlphaComponent(0),
    ]) {
        top.draw(in: NSRect(x: 0, y: cgSize.height * 0.55, width: cgSize.width, height: cgSize.height * 0.45), angle: 90)
    }

    // SF Symbol, white
    let pointSize = CGFloat(size) * 0.58
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symSize = sym.size
        let origin = NSPoint(
            x: (cgSize.width  - symSize.width)  / 2,
            y: (cgSize.height - symSize.height) / 2
        )

        // Render symbol image with white tint via NSImage(named:) trick:
        // draw into a tinted image so the symbol picks up the white fill.
        let tinted = NSImage(size: symSize, flipped: false) { rect in
            sym.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: NSRect(origin: origin, size: symSize),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else { return }
    let pngURL = outDir.appendingPathComponent("icon_\(size)x\(size).png")
    guard let dest = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, cgImage, nil)
    if !CGImageDestinationFinalize(dest) {
        FileHandle.standardError.write(Data("Failed to write \(pngURL.path)\n".utf8))
    }
    _ = scale
}

// macOS iconset wants these sizes (with @2x variants).
let entries: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, _) in entries {
    try renderPNG(size: size)
}

// Rename produced files to iconutil-expected names.
let producedNames = Set(entries.map { $0.0 }).sorted()
for size in producedNames {
    let src = outDir.appendingPathComponent("icon_\(size)x\(size).png")
    // Find which targets share this pixel size.
    let targets = entries.filter { $0.0 == size }.map { $0.1 }
    for (i, name) in targets.enumerated() {
        let dst = outDir.appendingPathComponent(name)
        if i == 0 {
            // First target replaces source.
            if dst.path != src.path {
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        } else {
            // Subsequent targets copy from first.
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: outDir.appendingPathComponent(targets[0]), to: dst)
        }
    }
}

// Invoke iconutil to bundle the iconset into AppIcon.icns
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", outDir.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    FileHandle.standardOutput.write(Data("Wrote \(icnsURL.path)\n".utf8))
} else {
    FileHandle.standardError.write(Data("iconutil failed with status \(iconutil.terminationStatus)\n".utf8))
    exit(1)
}
