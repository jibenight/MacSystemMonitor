#!/usr/bin/env swift
// Génère AppIcon.icns : symbole « jauge » blanc sur fond dégradé (squircle).
// Usage : swift make_icon.swift   →   produit AppIcon.icns dans le dossier courant.
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Fond : dégradé bleu → violet, dans un rectangle arrondi (squircle).
let radius = size * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
path.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.30, green: 0.45, blue: 0.95, alpha: 1.0),
    NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.92, alpha: 1.0)
])!
gradient.draw(in: rect, angle: -90)

// Symbole SF « jauge », teinté en blanc.
let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .regular)
if let sym = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                     accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    let symRect = NSRect(origin: .zero, size: sym.size)
    sym.draw(in: symRect)
    NSColor.white.set()
    symRect.fill(using: .sourceAtop)
    tinted.unlockFocus()

    // Centré, avec une légère ombre portée.
    let s = tinted.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    tinted.draw(at: origin, from: NSRect(origin: .zero, size: s),
                operation: .sourceOver, fraction: 1.0)
}

img.unlockFocus()

// Export PNG 1024.
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Échec de la génération PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("✅ icon_1024.png généré")
