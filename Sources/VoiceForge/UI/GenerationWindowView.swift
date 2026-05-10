import SwiftUI

struct GenerationWindowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isShowingSettings = false
    @State private var isShowingVoices = false

    var body: some View {
        ZStack {
            VoiceForgeBackground()

            HStack(alignment: .top, spacing: 22) {
                sidebar
                    .frame(width: 290)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heroPanel
                        referencePanel
                        composerPanel
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)

                inspectorPanel
                    .frame(width: 340)
            }
            .padding(24)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsWindowView()
                .environmentObject(viewModel)
                .frame(minWidth: 720, minHeight: 620)
        }
        .sheet(isPresented: $isShowingVoices) {
            CustomVoicesWindowView()
                .environmentObject(viewModel)
                .frame(minWidth: 860, minHeight: 680)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [VoiceForgeTheme.accent, VoiceForgeTheme.accentStrong],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("VoiceForge")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VoiceForgeTheme.sidebarText)
                        Text("Instant text to speech")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(VoiceForgeTheme.sidebarMutedText)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Generate speech")
                        .font(.system(size: 29, weight: .bold))
                        .tracking(-0.7)
                        .foregroundStyle(VoiceForgeTheme.sidebarText)
                    Text("Reference a voice, write the script, render, and replay without leaving the same surface.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VoiceForgeTheme.sidebarMutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sidebarNavRow(title: "Text to speech", subtitle: "Active workspace", systemImage: "waveform.badge.mic", active: true)
                    sidebarNavRow(title: "Voice library", subtitle: "Saved reference presets", systemImage: "person.2.crop.square.stack")
                    sidebarNavRow(title: "Workspace settings", subtitle: "Output and persistence", systemImage: "slider.horizontal.3")
                }

                HStack(spacing: 10) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .accessibilityIdentifier("openSettingsButton")

                    Button {
                        isShowingVoices = true
                    } label: {
                        Label("Voices", systemImage: "person.crop.rectangle.stack")
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .accessibilityIdentifier("openCustomVoicesButton")
                }
            }
            .padding(22)
            .voiceForgePanel(fill: VoiceForgeTheme.sidebar)

            VStack(alignment: .leading, spacing: 12) {
                Text("Ready checks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)

                VoiceForgeInfoRow(icon: "waveform", title: "Reference clip", detail: viewModel.referenceAudioPath.isEmpty ? "Load a sample clip to start cloning." : "Reference loaded and ready.")
                VoiceForgeInfoRow(icon: "character.cursor.ibeam", title: "Script", detail: viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Write the line you want spoken." : "Script staged for the next render.")
                VoiceForgeInfoRow(icon: "sparkles.rectangle.stack", title: "Output", detail: "Every render overwrites one predictable WAV for instant playback.")
            }
            .padding(20)
            .voiceForgePanel(fill: VoiceForgeTheme.panelStrong)

            Spacer(minLength: 0)
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Text to speech", systemImage: "waveform.badge.mic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.accentStrong)

                    Text("Instant text to speech")
                        .font(.system(size: 42, weight: .bold))
                        .tracking(-1.2)
                        .foregroundStyle(VoiceForgeTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A direct desktop clone of the fast TTS workflow: reference, script, generate, history, export.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 10) {
                    VoiceForgePill(text: viewModel.isGenerating ? "Generating" : "Ready", accent: viewModel.isGenerating)
                    Text("Fixed output")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                    Text(viewModel.outputLocationDescription)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 14) {
                VoiceForgeMetricTile(label: "Voice", value: viewModel.referenceAudioPath.isEmpty ? "No reference loaded" : "Reference clip loaded")
                VoiceForgeMetricTile(label: "Model", value: "Fish Audio S2 Pro")
                VoiceForgeMetricTile(label: "History", value: "\(viewModel.history.count) recent renders")
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.generate()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Label(viewModel.isGenerating ? "Rendering audio" : "Generate audio", systemImage: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(VoiceForgePrimaryButtonStyle())
                .disabled(viewModel.isGenerating)
                .accessibilityIdentifier("generateButton")

                VoiceForgePill(text: "Instant mode", accent: false)
                VoiceForgePill(text: "Reference cloning", accent: false)
                VoiceForgePill(text: "WAV output", accent: false)
            }
        }
        .padding(28)
        .voiceForgePanel(fill: Color.white.opacity(0.88))
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeader(
                eyebrow: "Reference voice",
                title: "Lock the voice once, then iterate on the script.",
                description: "Keep the reference pair stable and change the spoken line as often as needed."
            )

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        VoiceForgeField(
                            title: "Reference audio",
                            caption: "Use a clean clip under 30 seconds for the closest match."
                        ) {
                            TextField("Reference audio path", text: $viewModel.referenceAudioPath)
                                .textFieldStyle(.plain)
                                .foregroundStyle(VoiceForgeTheme.primaryText)
                                .accessibilityIdentifier("referenceAudioPathField")
                                .onChange(of: viewModel.referenceAudioPath) { _, _ in
                                    viewModel.persistReferenceFields()
                                }
                        }

                        Button("Choose audio") {
                            viewModel.chooseReferenceAudio()
                        }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        .padding(.top, 24)
                        .accessibilityIdentifier("chooseAudioButton")
                    }

                    VoiceForgeField(
                        title: "Reference transcript",
                        caption: "Match the spoken words in the clip closely so cloning stays stable."
                    ) {
                        TextField("Reference text", text: $viewModel.referenceText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .foregroundStyle(VoiceForgeTheme.primaryText)
                            .lineLimit(2, reservesSpace: true)
                            .accessibilityIdentifier("referenceTextField")
                            .onChange(of: viewModel.referenceText) { _, _ in
                                viewModel.persistReferenceFields()
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Reference tips")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)

                    VoiceForgeInfoRow(icon: "clock", title: "Under 30 seconds", detail: "Short clean clips clone more reliably.")
                    VoiceForgeInfoRow(icon: "captions.bubble", title: "Exact transcript", detail: "Match the spoken words closely.")
                    VoiceForgeInfoRow(icon: "tray.full", title: "Persistent session", detail: "Fields stay loaded between launches.")
                }
                .frame(width: 250)
            }
        }
        .padding(24)
        .voiceForgePanel()
    }

    private var composerPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeader(
                eyebrow: "Prompt and delivery",
                title: "Write the line and shape the delivery.",
                description: "Use one global tone plus inline tags for local emphasis."
            )

            HStack(alignment: .top, spacing: 18) {
                VoiceForgeField(
                    title: "Global tone",
                    caption: "Example: professional broadcast tone, whisper quietly, warm narrator."
                ) {
                    TextField("Emotion or tone", text: $viewModel.emotionText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(VoiceForgeTheme.primaryText)
                        .accessibilityIdentifier("emotionField")
                        .onChange(of: viewModel.emotionText) { _, _ in
                            viewModel.persistReferenceFields()
                        }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Direction")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)

                    VoiceForgeInfoRow(icon: "theatermasks", title: "Inline tags", detail: "Use *whisper* or *excited* for local direction.")
                    VoiceForgeInfoRow(icon: "slider.horizontal.below.rectangle", title: "Global tone", detail: "Set the overall performance once.")
                    VoiceForgeInfoRow(icon: "text.word.spacing", title: "Natural phrasing", detail: "Shorter lines usually sound cleaner.")
                }
                .frame(width: 250)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Quick inserts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)

                FlowLayout(viewModel.quickTags, spacing: 10) { tag in
                    Button {
                        viewModel.insertQuickTag(tag)
                    } label: {
                        VoiceForgePill(text: tag, accent: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickTag-\(tag)")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Script")
                    Spacer()
                    Label("\(viewModel.sourceText.count) chars", systemImage: "character.cursor.ibeam")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.secondaryText)

                PromptTextEditor(
                    text: $viewModel.sourceText,
                    pendingInsertion: viewModel.quickInsertText,
                    insertTrigger: viewModel.insertTrigger
                )
                .frame(minHeight: 280)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(VoiceForgeTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(VoiceForgeTheme.strokeStrong, lineWidth: 1)
                        )
                )

                HStack(spacing: 16) {
                    Label("Use inline tags for emphasis", systemImage: "sparkles")
                    Label("Preview updates live", systemImage: "eye")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .padding(24)
        .voiceForgePanel(fill: Color.white.opacity(0.9))
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                previewPanel
                outputPanel
                historyPanel
                statusPanel
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                eyebrow: "Formatted preview",
                title: "What the model receives.",
                description: nil
            )

            Text(viewModel.formattedPreview.isEmpty ? "Formatted prompt preview appears here." : viewModel.formattedPreview)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VoiceForgeTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                .padding(18)
                .accessibilityIdentifier("formattedPreviewText")
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(VoiceForgeTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(VoiceForgeTheme.strokeStrong, lineWidth: 1)
                        )
                )
        }
        .padding(22)
        .voiceForgePanel()
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                eyebrow: "Output",
                title: "Playback and export",
                description: "Controls unlock the moment a render lands."
            )

            HStack(spacing: 10) {
                Button {
                    viewModel.audioPlayer.togglePlayback()
                } label: {
                    Label(viewModel.audioPlayer.isPlaying ? "Pause" : "Play", systemImage: viewModel.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(VoiceForgeSecondaryButtonStyle())
                .disabled(viewModel.lastOutputURL == nil)
                .accessibilityIdentifier("playOutputButton")

                Button {
                    viewModel.saveOutputAs()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(VoiceForgeSecondaryButtonStyle())
                .disabled(viewModel.lastOutputURL == nil)
                .accessibilityIdentifier("saveOutputButton")

                Button {
                    viewModel.revealOutputInFinder()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(VoiceForgeSecondaryButtonStyle())
                .disabled(viewModel.lastOutputURL == nil)
                .accessibilityIdentifier("revealOutputButton")
            }

            if let lastOutputURL = viewModel.lastOutputURL {
                Text(lastOutputURL.path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .textSelection(.enabled)
            } else {
                Text("No render available yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }
        }
        .padding(22)
        .voiceForgePanel()
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                eyebrow: "History",
                title: "Recent generations",
                description: "Recent renders stay beside the composer for quick recall."
            )

            if viewModel.history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nothing generated yet", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.primaryText)
                    Text("Your newest renders will appear here after the first generation.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(VoiceForgeTheme.panelMuted)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.history) { item in
                            HStack(alignment: .top, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "waveform.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(VoiceForgeTheme.accent)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.sourceText)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(VoiceForgeTheme.primaryText)
                                            .lineLimit(2)
                                        Text(item.formattedPrompt)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                                            .lineLimit(2)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                                    }

                                    Spacer(minLength: 8)

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    viewModel.loadHistory(item)
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                            .font(.system(size: 18))
                                        Text("Reuse")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(VoiceForgeTheme.accentStrong)
                                    .frame(width: 56)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("historyReuseButton-\(item.id.uuidString)")
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(VoiceForgeTheme.field)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .onTapGesture {
                                viewModel.loadHistory(item)
                            }
                            .accessibilityIdentifier("historyEntry-\(item.id.uuidString)")
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 260)
                .accessibilityIdentifier("historyList")
            }
        }
        .padding(22)
        .voiceForgePanel(fill: Color.white.opacity(0.9))
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                eyebrow: "Session status",
                title: viewModel.generationError.isEmpty ? "Render status and shell output." : "Generation needs attention.",
                description: nil
            )

            if !viewModel.generationError.isEmpty {
                Text(viewModel.generationError)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.98, green: 0.92, blue: 0.9))
                    )
            } else {
                Text(viewModel.isGenerating ? "VoiceForge is running `mlx-speech` and will enable playback when the output file lands." : "Ready for the next line. Reference voice, preview text, and output path are all in sync.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }

            if !viewModel.cliOutput.isEmpty {
                ScrollView {
                    Text(viewModel.cliOutput)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(minHeight: 120, maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(VoiceForgeTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(VoiceForgeTheme.strokeStrong, lineWidth: 1)
                        )
                )
            }
        }
        .padding(22)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private func panelHeader(eyebrow: String, title: String, description: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VoiceForgePill(text: eyebrow, accent: false)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(VoiceForgeTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let description {
                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sidebarNavRow(title: String, subtitle: String, systemImage: String, active: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.white : VoiceForgeTheme.sidebarText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(active ? VoiceForgeTheme.accent : VoiceForgeTheme.sidebarElevated.opacity(0.95))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.sidebarText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.sidebarMutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(active ? VoiceForgeTheme.sidebarElevated : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(active ? Color.white.opacity(0.08) : Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    private let data: Data
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content

    init(_ data: Data, spacing: CGFloat, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: spacing)], alignment: .leading, spacing: spacing) {
                    ForEach(Array(data), id: \.self) { item in
                        content(item)
                    }
                }
            }
            Spacer()
        }
    }
}
