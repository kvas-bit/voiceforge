import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    // Force the sidebar visible on launch and keep it that way; we never collapse it programmatically.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: inspectorBinding) {
                    StudioInspectorView()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                }
                .toolbar { studioToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("VoiceForge")
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.inspectorVisible && viewModel.destination == .studio },
            set: { viewModel.inspectorVisible = $0 }
        )
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
            Label {
                Text("VoiceForge")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoiceForgeTheme.primaryText)
            } icon: {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.accent)
            }
            .labelStyle(.titleAndIcon)
            .fixedSize()
        }
        ToolbarItem(placement: .principal) {
            StatusPill(isGenerating: viewModel.isGenerating)
        }
        ToolbarItem(placement: .primaryAction) {
            if viewModel.isGenerating {
                Button(role: .destructive) {
                    viewModel.cancelGeneration()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityIdentifier("cancelGenerateButton")
                .help("Stop the in-flight generation (⌘.)")
            } else {
                Button {
                    viewModel.generate()
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.destination != .studio)
                .accessibilityIdentifier("generateButton")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.inspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Toggle inspector")
            .disabled(viewModel.destination != .studio)
        }
    }
}

private struct StatusPill: View {
    let isGenerating: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(isGenerating ? Color.orange : VoiceForgeTheme.success)
                .frame(width: 6, height: 6)
            Text(isGenerating ? "Generating" : "Ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VoiceForgeTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(VoiceForgeTheme.fieldMuted)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(VoiceForgeTheme.stroke, lineWidth: 0.5)
                )
        )
        .fixedSize()
    }
}

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        // Bridge non-optional destination binding into the Optional binding `List(selection:)`
        // expects. We never write `nil` back, so selection never resets.
        let selection = Binding<SidebarDestination?>(
            get: { viewModel.destination },
            set: { new in
                if let new { viewModel.destination = new }
            }
        )

        List(selection: selection) {
            Section("Workspace") {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.label, systemImage: destination.systemImage)
                        .tag(Optional(destination))
                        .accessibilityIdentifier("sidebarRow-\(destination.rawValue)")
                }
            }
            Section("Account") {
                // Not part of the selection set; kept as a plain row so it can't steal selection.
                Label("Subscription", systemImage: "creditcard")
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .accessibilityIdentifier("sidebarRow-subscription")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            // Reserve space for traffic lights now that the titlebar is hidden.
            Color.clear.frame(height: 28)
        }
    }
}
