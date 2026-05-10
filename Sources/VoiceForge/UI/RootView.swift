import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            destinationView
                .inspector(isPresented: $viewModel.inspectorVisible) {
                    StudioInspectorView()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                }
                .toolbar { studioToolbar }
        }
        .navigationTitle("VoiceForge")
    }

    @ViewBuilder
    private var destinationView: some View {
        switch viewModel.destination {
        case .studio:
            StudioView()
        case .voices:
            VoicesView()
        case .history:
            HistoryView()
        }
    }

    @ToolbarContentBuilder
    private var studioToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .foregroundStyle(VoiceForgeTheme.accent)
                Text("VoiceForge")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isGenerating ? Color.orange : VoiceForgeTheme.success)
                    .frame(width: 7, height: 7)
                Text(viewModel.isGenerating ? "Generating" : "Ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.generate()
            } label: {
                Label("Generate", systemImage: viewModel.isGenerating ? "hourglass" : "sparkles")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isGenerating || viewModel.destination != .studio)
            .accessibilityIdentifier("generateButton")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.inspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Toggle inspector")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.destination) {
            Section("Workspace") {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.label, systemImage: destination.systemImage)
                        .tag(destination)
                        .accessibilityIdentifier("sidebarRow-\(destination.rawValue)")
                }
            }
            Section("Account") {
                Label("Subscription", systemImage: "creditcard")
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .accessibilityIdentifier("sidebarRow-subscription")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            // Reserve space for traffic lights when the titlebar is hidden.
            Color.clear.frame(height: 28)
        }
    }
}
