import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

@main
struct VoiceForgeApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-state") {
            clearUITestState()
        }
    }

    var body: some Scene {
        WindowGroup("Generation + History", id: "main") {
            GenerationWindowView()
                .environmentObject(viewModel)
                .frame(minWidth: 1240, minHeight: 820)
        }
        .defaultSize(width: 1480, height: 940)
    }

    private func clearUITestState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: VoiceForgeStorageKeys.referenceAudioPath)
        defaults.removeObject(forKey: VoiceForgeStorageKeys.referenceText)
        defaults.removeObject(forKey: VoiceForgeStorageKeys.emotionText)
        defaults.removeObject(forKey: VoiceForgeStorageKeys.voicePresets)

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let historyURL = baseDirectory?
            .appendingPathComponent("VoiceForge", isDirectory: true)
            .appendingPathComponent("history.json")

        if let historyURL {
            try? FileManager.default.removeItem(at: historyURL)
        }

        let savedStateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("com.kaviantoniovasudeo.VoiceForge.savedState", isDirectory: true)

        try? FileManager.default.removeItem(at: savedStateURL)
    }
}
