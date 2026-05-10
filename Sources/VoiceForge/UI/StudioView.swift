import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct StudioView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    referenceCard
                    editorCard
                    previewCard
                    if !viewModel.generationError.isEmpty || !viewModel.cliOutput.isEmpty {
                        statusCard
                    }
                }
                .padding(20)
            }
            PlaybackDockView()
        }
        .navigationTitle("Studio")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Studio")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                Text("Write the script, pick a voice, and generate. Type [ to insert audio tags inline.")
                    .font(.system(size: 13))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                VoiceForgePill(text: viewModel.isGenerating ? "Generating" : "Ready", accent: viewModel.isGenerating)
                Text("\(viewModel.sourceText.count) characters")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
    }

    private var referenceCard: some View {
        let preset = viewModel.presets.first { $0.id == viewModel.selectedPresetID }
        let hasReference = !viewModel.referenceAudioPath.isEmpty
        let displayName: String = {
            if let preset { return preset.name }
            if hasReference {
                return URL(fileURLWithPath: viewModel.referenceAudioPath)
                    .deletingPathExtension()
                    .lastPathComponent
            }
            return "No voice selected"
        }()
        let detail: String = {
            if preset != nil { return "Saved voice preset" }
            if hasReference { return "Loose reference clip" }
            return "Open Voices to add or pick one"
        }()

        return HStack(spacing: 14) {
            Circle()
                .fill(VoiceForgeTheme.accentSoft)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: hasReference ? "waveform" : "person.crop.circle.dashed")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.accent)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Label("Reference voice", systemImage: "person.wave.2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                        .labelStyle(.titleAndIcon)
                }
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if hasReference {
                let previewID = preset?.id ?? AppViewModel.looseReferencePreviewID
                Button {
                    let url = URL(fileURLWithPath: viewModel.referenceAudioPath)
                    viewModel.togglePreview(voiceID: previewID, url: url)
                } label: {
                    Image(systemName: viewModel.isPreviewing(voiceID: previewID) ? "pause.circle" : "play.circle")
                        .font(.system(size: 20))
                }
                .buttonStyle(.borderless)
                .help(viewModel.isPreviewing(voiceID: previewID) ? "Pause preview" : "Preview reference clip")
                .accessibilityIdentifier("studioPreviewVoiceButton")
            }

            Menu {
                ForEach(viewModel.presets) { preset in
                    Button(preset.name) {
                        viewModel.selectedPresetID = preset.id
                        viewModel.applyPreset(preset)
                    }
                }
                if !viewModel.presets.isEmpty {
                    Divider()
                }
                Button("Manage voices…") {
                    viewModel.destination = .voices
                }
            } label: {
                Label("Choose voice", systemImage: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 150)
            .accessibilityIdentifier("studioVoicePickerMenu")
        }
        .padding(14)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Script", systemImage: "text.cursor")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(viewModel.sourceText.count) chars")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }

            PromptTextEditor(
                text: $viewModel.sourceText,
                pendingInsertion: viewModel.quickInsertText,
                insertTrigger: viewModel.insertTrigger
            )
            .frame(minHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VoiceForgeTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick tags")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.quickTags, id: \.self) { tag in
                        Button {
                            viewModel.insertQuickTag(tag)
                        } label: {
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(VoiceForgeTheme.tagText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(VoiceForgeTheme.tagBackground)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quickTag-\(tag)")
                    }
                }
            }
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Formatted prompt preview", systemImage: "eye")
                .font(.system(size: 13, weight: .semibold))
            Text(viewModel.formattedPreview.isEmpty ? "Formatted prompt preview appears here." : viewModel.formattedPreview)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VoiceForgeTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VoiceForgeTheme.fieldMuted)
                )
                .accessibilityIdentifier("formattedPreviewText")
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(viewModel.generationError.isEmpty ? "Generator output" : "Generation error", systemImage: viewModel.generationError.isEmpty ? "terminal" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewModel.generationError.isEmpty ? VoiceForgeTheme.secondaryText : VoiceForgeTheme.danger)
            if !viewModel.generationError.isEmpty {
                Text(viewModel.generationError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.danger)
            }
            if !viewModel.cliOutput.isEmpty {
                ScrollView {
                    Text(viewModel.cliOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VoiceForgeTheme.fieldMuted)
                )
            }
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }
}

/// Simple flow layout used to wrap pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var widths: [CGFloat] = [0]
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            if widths[widths.count - 1] + needed > maxWidth {
                rows.append([size])
                widths.append(size.width)
            } else {
                rows[rows.count - 1].append(size)
                widths[widths.count - 1] += needed
            }
        }
        let height = rows.reduce(CGFloat(0)) { acc, row in
            acc + (row.map(\.height).max() ?? 0) + spacing
        } - spacing
        return CGSize(width: widths.max() ?? 0, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
