import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
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
        .onChange(of: viewModel.destination) { _, destination in
            // A destination's internal layout must never be allowed to trade away
            // the app-level navigation column. History is the widest destination,
            // so explicitly restore the user's navigation affordance on entry.
            if destination == .history {
                columnVisibility = .all
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.inspectorVisible && viewModel.destination == .studio },
            set: { isPresented in
                // SwiftUI dismisses an inspector as its destination disappears.
                // That transient dismissal is not a user preference change.
                guard viewModel.destination == .studio else { return }
                viewModel.inspectorVisible = isPresented
            }
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
        case .conversations:
            ConversationsView()
        }
    }

    @ToolbarContentBuilder
    private var studioToolbar: some ToolbarContent {
        if viewModel.destination == .studio {
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
                .accessibilityIdentifier("inspectorToggleButton")
            }
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
