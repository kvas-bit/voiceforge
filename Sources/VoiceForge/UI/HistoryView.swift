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
                .frame(minWidth: 280)
            detail
                .frame(minWidth: 320)
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
                        draftName: $draftName,
                        commitRename: { commitRename(for: item) },
                        beginRename: { beginRename(for: item) }
                    )
                    .tag(item.id)
                    .contextMenu {
                        Button("Rename") { beginRename(for: item) }
                        Button("Reuse in Studio") {
                            viewModel.loadHistory(item)
                            viewModel.destination = .studio
                        }
                        Button("Play") { viewModel.playHistory(item) }
                        Button("Copy prompt") { viewModel.copyPrompt(item) }
                        Button("Reveal in Finder") {
                            let url = URL(fileURLWithPath: item.outputPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            viewModel.deleteHistory(item)
                        }
                    }
                    .accessibilityIdentifier("historyEntry-\(item.id.uuidString)")
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
            VStack(alignment: .leading, spacing: 14) {
                HStack {
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
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            beginRename(for: item)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        .accessibilityIdentifier("historyRenameButton-\(item.id.uuidString)")

                        Button {
                            viewModel.loadHistory(item)
                            viewModel.destination = .studio
                        } label: {
                            Label("Reuse", systemImage: "arrow.uturn.left.circle")
                        }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        .accessibilityIdentifier("historyReuseButton-\(item.id.uuidString)")
                    }
                }

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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    Text(item.referenceAudioPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                    Text(item.referenceText)
                        .font(.system(size: 11))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.playHistory(item)
                    } label: {
                        Label(viewModel.audioPlayer.isPlaying ? "Pause" : "Play", systemImage: viewModel.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(VoiceForgePrimaryButtonStyle())

                    Button {
                        viewModel.copyPrompt(item)
                    } label: {
                        Label("Copy prompt", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())

                    Button(role: .destructive) {
                        viewModel.deleteHistory(item)
                        selectedID = nil
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                }

                Spacer()
            }
            .padding(20)
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
}

private struct HistoryRow: View {
    let item: GenerationHistoryItem
    let isRenaming: Bool
    @Binding var draftName: String
    let commitRename: () -> Void
    let beginRename: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(VoiceForgeTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                if isRenaming {
                    TextField("Name", text: $draftName, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityIdentifier("historyRowRenameField-\(item.id.uuidString)")
                } else {
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .onTapGesture(count: 2, perform: beginRename)
                }
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .padding(.vertical, 4)
    }
}
