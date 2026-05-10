import AppKit

/// Polishes raster dock assets so runtime `applicationIconImage` tiles read like finished macOS
/// app icons: squircle clip, contrasting hairline stroke, subtle highlight from the lighting direction.
///
/// Bundled `AppIcon.icns` still handles Finder Spotlight; here we mimic “finished icon” cues for Dock.
enum DockTileIconCompositor {
    /// macOS squircle curvature from the Apple 1024 pt template (~227 pt corner radius).
    private static let cornerRadiusFactor: CGFloat = 227 / 1024

    static func polishedDockIcon(assetName: String, prefersDark: Bool) -> NSImage? {
        polishedImage(assetName: assetName, prefersDark: prefersDark, pixelSide: 1024)
    }

    static func toolbarBrandBadge(assetName: String, prefersDark: Bool) -> NSImage? {
        polishedImage(assetName: assetName, prefersDark: prefersDark, pixelSide: 96)
    }

    private static func polishedImage(assetName: String, prefersDark: Bool, pixelSide: CGFloat) -> NSImage? {
        guard let source = NSImage(named: NSImage.Name(assetName)) else { return nil }

        let composed = NSImage(size: NSSize(width: pixelSide, height: pixelSide))
        composed.lockFocus()
        defer { composed.unlockFocus() }

        guard let gc = NSGraphicsContext.current?.cgContext else {
            composed.unlockFocus()
            return source
        }

        let rect = CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        let cornerRadius = min(rect.width, rect.height) * cornerRadiusFactor

        NSGraphicsContext.current?.imageInterpolation = .high
        gc.setAllowsAntialiasing(true)

        NSGraphicsContext.saveGraphicsState()

        let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()

        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()

        clipPath.addClip()

        gc.saveGState()
        gc.setAllowsAntialiasing(true)
        let spotlightAlpha: CGFloat = prefersDark ? 0.07 : 0.09
        let colors = [
            NSColor(calibratedWhite: 1, alpha: spotlightAlpha).cgColor,
            NSColor(calibratedWhite: 1, alpha: 0).cgColor,
        ] as CFArray
        if let cgSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let grad = CGGradient(colorsSpace: cgSpace, colors: colors, locations: [0.0, 1.0])
        {
            gc.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.midX, y: rect.maxY * 1.04),
                end: CGPoint(x: rect.midX, y: rect.midY),
                options: [.drawsAfterEndLocation]
            )
        }
        gc.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        let strokeWidth: CGFloat =
            pixelSide < 200
                ? max(0.95, pixelSide * 0.012)
                : max(2, pixelSide * 0.0023)
        clipPath.lineWidth = strokeWidth
        (prefersDark
            ? NSColor(calibratedWhite: 1.0, alpha: 0.18)
            : NSColor(calibratedWhite: 0.0, alpha: 0.09)).setStroke()
        clipPath.stroke()

        return composed
    }
}
