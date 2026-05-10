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
        WindowGroup("VoiceForge", id: "main") {
            rootContent
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { VoiceForgeCommands(viewModel: viewModel) }

        Settings {
            SettingsScene()
                .environmentObject(viewModel)
                .frame(minWidth: 540, minHeight: 360)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        let base = RootView()
            .environmentObject(viewModel)
            .frame(minWidth: 1100, minHeight: 720)
        if #available(macOS 15.0, *) {
            base.containerBackground(.regularMaterial, for: .window)
        } else {
            base.background(.regularMaterial)
        }
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

private struct VoiceForgeCommands: Commands {
    @ObservedObject var viewModel: AppViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Generation") {
                viewModel.sourceText = ""
                viewModel.destination = .studio
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Studio") {
            Button("Generate") { viewModel.generate() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isGenerating)
            Button(viewModel.audioPlayer.isPlaying ? "Pause Output" : "Play Output") {
                viewModel.audioPlayer.togglePlayback()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(viewModel.lastOutputURL == nil)
            Divider()
            Button("Reveal Output in Finder") { viewModel.revealOutputInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.lastOutputURL == nil)
            Button("Save Output As…") { viewModel.saveOutputAs() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(viewModel.lastOutputURL == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Studio") { viewModel.destination = .studio }
                .keyboardShortcut("1", modifiers: .command)
            Button("Voices") { viewModel.destination = .voices }
                .keyboardShortcut("2", modifiers: .command)
            Button("History") { viewModel.destination = .history }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}
