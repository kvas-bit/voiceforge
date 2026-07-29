import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

@main
struct VoiceForgeApp: App {
    @StateObject private var viewModel: AppViewModel

    init() {
        let vm: AppViewModel
        if ProcessInfo.processInfo.arguments.contains("--uitest-mock-generation") {
            // UI-test mode: isolated storage + mock generation that writes
            // synthetic WAV to a temp root without touching Application Support.
            let store = HistoryStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("VoiceForge-UI-Test-\(UUID().uuidString)")
                    .appendingPathComponent("history.json")
            )
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoiceForge-UI-Test-Output")
            let mockService = SpeechGenerationService.__internalInit(
                executableURL: nil, renderRoot: tempRoot,
                fileManager: .default, runner: SpeechGenerationService.launchProcess,
                usePersistent: false,
                mockGenerate: { request in
                    // Write a minimal silent WAV and return a fake result.
                    let outURL = try SpeechGenerationService.__tempOutputURL(forID: request.id, under: tempRoot)
                    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    let header = Data([
                        0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00,
                        0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
                        0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
                        0x40, 0x1F, 0x00, 0x00, 0x80, 0x3E, 0x00, 0x00,
                        0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61,
                        0x00, 0x00, 0x00, 0x00
                    ])
                    try header.write(to: outURL)
                    return GenerationResult(formattedPrompt: "[mock] \(request.sourceText)",
                        outputURL: outURL, standardOutput: "", standardError: "")
                }
            )
            let testSuiteName = "VoiceForgeUITest-\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: testSuiteName)!
            testDefaults.removePersistentDomain(forName: testSuiteName)
            vm = AppViewModel(defaults: testDefaults, historyStore: store,
                              generationService: mockService)
        } else {
            vm = AppViewModel()
        }
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some Scene {
        WindowGroup("VoiceForge", id: "main") {
            rootContent
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task {
                        await viewModel.shutdownService()
                        await viewModel.shutdownOllamaIfOwned()
                    }
                }
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
}

private struct VoiceForgeCommands: Commands {
    @ObservedObject var viewModel: AppViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Generation") {
                viewModel.sourceText = ""
                viewModel.clearRegenerationSource()
                viewModel.destination = .studio
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Studio") {
            if viewModel.isGenerating {
                Button("Cancel Generation") { viewModel.cancelGeneration() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Generate") { viewModel.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
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
