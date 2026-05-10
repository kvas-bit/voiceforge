import AppKit

private enum DistributedAppleInterfaceThemeObservation {
    /// Hooks system-wide light/dark changes so Dock icon updates without waiting for SwiftUI redraws.
    nonisolated static let installOnce: Void = {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in DockApplicationIconUpdater.refreshFromSystemAppearance() }
        }
        return ()
    }()
}

/// Adaptive dock tile for macOS system appearance.
///
/// `AppIcon.appiconset` only produces one `AppIcon.icns`; dark luminosity siblings for
/// macOS app icons are ignored by Asset Catalog tooling. We still ship canonical sizes
/// in the catalog for Finder / Spotlight, while the Dock listens to appearance changes
/// and swaps `applicationIconImage` between `DockIconLight` and `DockIconDark`.
enum DockApplicationIconUpdater {
    nonisolated private static func appearancePrefersDark(_ appearance: NSAppearance) -> Bool {
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua { return true }
        if appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
            == .accessibilityHighContrastDarkAqua
        {
            return true
        }
        return false
    }

    private static func imageForAppearance(_ prefersDark: Bool) -> NSImage? {
        NSImage(named: prefersDark ? "DockIconDark" : "DockIconLight")
    }

    @MainActor
    static func refreshFromSystemAppearance() {
        let prefersDark = appearancePrefersDark(NSApplication.shared.effectiveAppearance)
        guard let dockImage = imageForAppearance(prefersDark) else {
            NSLog("[VoiceForge] Missing Dock icon assets (DockIconLight / DockIconDark).")
            return
        }
        NSApplication.shared.applicationIconImage = dockImage
    }

    nonisolated static func installDistributedThemeObserverIfNeeded() {
        _ = DistributedAppleInterfaceThemeObservation.installOnce
    }
}
