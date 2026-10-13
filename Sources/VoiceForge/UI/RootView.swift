import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isShowingGenerationSettings = false

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
        .sheet(isPresented: $isShowingGenerationSettings) {
            GenerationSettingsView()
                .environmentObject(viewModel)
                .frame(minWidth: 560, minHeight: 540)
        }
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
                DispatchQueue.main.async {
                    guard viewModel.destination == .studio,
                          viewModel.inspectorVisible != isPresented else { return }
                    viewModel.inspectorVisible = isPresented
                }
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
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingGenerationSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Generation settings")
                .accessibilityLabel("Generation settings")
                .accessibilityIdentifier("settingsButton")
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

    private var destinationSelection: Binding<SidebarDestination> {
        Binding(
            get: { viewModel.destination },
            set: { destination in
                guard viewModel.destination != destination else { return }
                DispatchQueue.main.async {
                    viewModel.destination = destination
                }
            }
        )
    }

    var body: some View {
        // Keep rows as plain labels with tags. Defer the selection write so the
        // ObservableObject does not publish while SwiftUI is updating the List.
        List(selection: destinationSelection) {
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
