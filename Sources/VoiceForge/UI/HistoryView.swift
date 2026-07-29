import AppKit
import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct HistoryView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedID: GenerationHistoryItem.ID?
    @State private var renamingID: GenerationHistoryItem.ID?
    @State private var draftName: String = ""

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 230, idealWidth: 290, maxWidth: 360)
            detail
                .frame(minWidth: 260)
        }
        .navigationTitle("History")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent generations")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !viewModel.history.isEmpty {
                    Menu {
                        Button("Clear history", role: .destructive) {
                            viewModel.clearHistory()
                            selectedID = nil
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            List(selection: $selectedID) {
                ForEach(viewModel.history) { item in
                    HistoryRow(
                        item: item,
                        isRenaming: renamingID == item.id,
                        isPlaying: viewModel.isPlayingHistory(item),
                        draftName: $draftName,
                        commitRename: { commitRename(for: item) },
                        beginRename: { beginRename(for: item) },
                        select: { selectedID = item.id },
                        togglePlay: { viewModel.togglePlayHistory(item) },
                        downloadToDownloads: { viewModel.downloadHistoryItemToDownloads(item) }
                    )
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedID = item.id
                    }
                    .contextMenu {
                        Button("Rename") { beginRename(for: item) }
                        Button(item.type == .conversation ? "Open in Conversations" : "Reuse in Studio") {
                            if item.type == .conversation {
                                viewModel.loadConversation(item)
                            } else {
                                viewModel.loadHistory(item)
                                viewModel.destination = .studio
                            }
                        }
                        Button(item.type == .conversation ? "Open and play" : "Play") {
                            viewModel.playHistory(item)
                        }
                        if item.type == .single {
                            Button("Copy prompt") { viewModel.copyPrompt(item) }
                        }
                        Button("Reveal in Finder") {
                            let url = URL(fileURLWithPath: item.outputPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Button(item.type == .conversation ? "Download merged WAV" : "Download to Downloads") {
                            viewModel.downloadHistoryItemToDownloads(item)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            viewModel.deleteHistory(item)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("historyList")
        }
    }

    private func beginRename(for item: GenerationHistoryItem) {
        renamingID = item.id
        draftName = item.name
    }

    private func commitRename(for item: GenerationHistoryItem) {
        if renamingID == item.id {
            viewModel.renameHistory(item, to: draftName)
        }
        renamingID = nil
        draftName = ""
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let item = viewModel.history.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) {
                            historyTitle(for: item)
                            Spacer(minLength: 12)
                            historyHeaderActions(for: item)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            historyTitle(for: item)
                            historyHeaderActions(for: item)
                        }
                    }

                    if let sourceID = item.regeneratedFromID {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            Text("Version of")
                                .font(.system(size: 11))
                                .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            if let original = viewModel.history.first(where: { $0.id == sourceID }) {
                                Button(original.name) {
                                    selectedID = original.id
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VoiceForgeTheme.accent)
                            } else {
                                Text("an earlier generation (no longer in history)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            }
                        }
                        .accessibilityIdentifier("historyVersionOfLink")
                    }

                    if item.type == .single {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Formatted prompt")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            Text(item.formattedPrompt)
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(VoiceForgeTheme.fieldMuted)
                                )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Conversation")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            Text("\((item.conversationLines ?? []).count) line\(((item.conversationLines ?? []).count == 1) ? "" : "s") saved in this bundle.")
                                .font(.system(size: 13))
                                .foregroundStyle(VoiceForgeTheme.secondaryText)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(VoiceForgeTheme.fieldMuted)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reference")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                        Text(item.referenceAudioPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(item.referenceAudioPath)
                        Text(item.referenceText)
                            .font(.system(size: 11))
                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        Button {
                            viewModel.togglePlayHistory(item)
                        } label: {
                            if item.type == .conversation {
                                Label("Open & Play", systemImage: "play.square")
                            } else {
                                let playing = viewModel.isPlayingHistory(item)
                                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                            }
                        }
                        .buttonStyle(VoiceForgePrimaryButtonStyle())
                        .accessibilityIdentifier("historyDetailPlayButton")

                        if item.type == .single {
                            Button {
                                viewModel.copyPrompt(item)
                            } label: {
                                Label("Copy prompt", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        }

                        Button {
                            viewModel.downloadHistoryItemToDownloads(item)
                        } label: {
                            Label(
                                item.type == .conversation ? "Download merged WAV" : "Download",
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        .accessibilityIdentifier("historyDetailDownloadButton")

                        Button(role: .destructive) {
                            viewModel.deleteHistory(item)
                            selectedID = nil
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                Text(viewModel.history.isEmpty ? "Nothing generated yet" : "Select a generation")
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.history.isEmpty
                     ? "Your newest renders will show up here after the first generation."
                     : "Pick an entry from the list to inspect its prompt and audio.")
                    .font(.system(size: 12))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }

    private func historyTitle(for item: GenerationHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.createdAt.formatted(date: .long, time: .shortened))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)
            if renamingID == item.id {
                TextField("Name", text: $draftName, onCommit: { commitRename(for: item) })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier("historyDetailRenameField")
            } else {
                Text(item.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.primaryText)
                    .lineLimit(2)
                    .onTapGesture(count: 2) { beginRename(for: item) }
            }
            Text(item.sourceText)
                .font(.system(size: 12))
                .foregroundStyle(VoiceForgeTheme.secondaryText)
                .lineLimit(3)
        }
    }

    private func historyHeaderActions(for item: GenerationHistoryItem) -> some View {
        HStack(spacing: 8) {
            Button {
                beginRename(for: item)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(VoiceForgeSecondaryButtonStyle())
            .accessibilityIdentifier("historyRenameButton-\(item.id.uuidString)")

            Button {
                if item.type == .conversation {
                    viewModel.loadConversation(item)
                } else {
                    viewModel.loadHistory(item)
                    viewModel.destination = .studio
                }
            } label: {
                Label(
                    item.type == .conversation ? "Open" : "Reuse",
                    systemImage: item.type == .conversation ? "text.badge.plus" : "arrow.uturn.left.circle"
                )
            }
            .buttonStyle(VoiceForgeSecondaryButtonStyle())
            .accessibilityIdentifier("historyReuseButton-\(item.id.uuidString)")
        }
    }
}

private struct HistoryRow: View {
    let item: GenerationHistoryItem
    let isRenaming: Bool
    let isPlaying: Bool
    @Binding var draftName: String
    let commitRename: () -> Void
    let beginRename: () -> Void
    let select: () -> Void
    let togglePlay: () -> Void
    let downloadToDownloads: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Per-row play/pause toggle. Using .buttonStyle(.plain) so the row's
            // List selection isn't stolen by the button hit-test.
            Button(action: togglePlay) {
                Image(systemName: rowPlayImage)
                    .font(.system(size: 22))
                    .foregroundStyle(VoiceForgeTheme.accent)
            }
            .buttonStyle(.plain)
            .help(rowPlayHelp)
            .accessibilityIdentifier("historyRowPlayButton-\(item.id.uuidString)")

            Button(action: downloadToDownloads) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(item.type == .conversation ? "Download merged WAV to Downloads" : "Copy WAV to Downloads")
            .accessibilityIdentifier("historyRowDownloadButton-\(item.id.uuidString)")

            if isRenaming {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $draftName, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityIdentifier("historyRowRenameField-\(item.id.uuidString)")
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
            } else {
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded(beginRename))
                .accessibilityIdentifier("historyRowSelect-\(item.id.uuidString)")
            }
        }
        .padding(.vertical, 4)
    }

    private var rowPlayImage: String {
        item.type == .conversation ? "play.square" : (isPlaying ? "pause.circle.fill" : "play.circle.fill")
    }

    private var rowPlayHelp: String {
        item.type == .conversation ? "Open and play conversation" : (isPlaying ? "Pause" : "Play")
    }
}
