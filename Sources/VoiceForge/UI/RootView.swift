import AppKit
import Combine
import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
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
        .onAppear { DockApplicationIconUpdater.refreshFromSystemAppearance() }
        .onChange(of: colorScheme) { _, _ in
            DockApplicationIconUpdater.refreshFromSystemAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DockApplicationIconUpdater.refreshFromSystemAppearance()
        }
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
            HStack(spacing: 9) {
                let prefersDarkBadge = colorScheme == .dark
                if let badge = DockTileIconCompositor.toolbarBrandBadge(
                    assetName: prefersDarkBadge ? "DockIconDark" : "DockIconLight",
                    prefersDark: prefersDarkBadge
                ) {
                    Image(nsImage: badge)
                        .resizable()
                        .interpolation(Image.Interpolation.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26)
                }
                Text("VoiceForge")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoiceForgeTheme.primaryText)
                    .fixedSize()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.45), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(VoiceForgeTheme.stroke.opacity(0.95), lineWidth: 1)
            )
            .fixedSize()
            .accessibilityIdentifier("appWordmark")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("VoiceForge")
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

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        // Bind List(selection:) directly to the non-optional destination. Each row is a
        // plain Label with a matching .tag — never a Button or .onTapGesture, because
        // either of those would intercept the row's hit-test and prevent selection.
        List(selection: $viewModel.destination) {
            Section("Workspace") {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.label, systemImage: destination.systemImage)
                        .tag(destination)
                        .accessibilityIdentifier("sidebar\(destination.label)")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            // Reserve space for traffic lights now that the titlebar is hidden.
            Color.clear.frame(height: 28)
        }
    }
}
