import AppKit
import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

@MainActor
protocol TagAutocompleteControllerDelegate: AnyObject {
    func autocomplete(_ controller: TagAutocompleteController, didCommit tag: AudioTag, replacingRange: NSRange)
}

/// Borderless floating panel that lists `AudioTag` suggestions near the caret.
/// Anchored in screen coordinates; arrow keys + Return / Tab / Escape work via the text view's
/// `doCommandBy:` shim because this panel is non-key.
@MainActor
final class TagAutocompleteController {
    private weak var delegate: TagAutocompleteControllerDelegate?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AutocompleteList>?
    private(set) var suggestions: [AudioTag] = []
    private(set) var selectionIndex: Int = 0
    private var bracketIndex: Int = 0
    private var caretIndex: Int = 0

    var isVisible: Bool { panel?.isVisible == true }

    init(delegate: TagAutocompleteControllerDelegate) {
        self.delegate = delegate
    }

    func show(at screenRect: NSRect, query: String, bracketIndex: Int, caretIndex: Int) {
        self.bracketIndex = bracketIndex
        self.caretIndex = caretIndex
        suggestions = TagCatalog.suggestions(matching: query, limit: 8)
        if suggestions.isEmpty {
            dismiss()
            return
        }
        selectionIndex = min(selectionIndex, suggestions.count - 1)
        updateContent()

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isFloatingPanel = true
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            self.panel = panel
        }

        guard let panel else { return }
        let origin = NSPoint(x: screenRect.minX, y: screenRect.minY - 220)
        panel.setFrameTopLeftPoint(NSPoint(x: origin.x, y: screenRect.minY))
        panel.orderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        selectionIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !suggestions.isEmpty else { return }
        let count = suggestions.count
        selectionIndex = (selectionIndex + delta + count) % count
        updateContent()
    }

    func commitSelection() {
        guard let delegate, suggestions.indices.contains(selectionIndex) else {
            dismiss(); return
        }
        let tag = suggestions[selectionIndex]
        let range = NSRange(location: bracketIndex, length: max(0, caretIndex - bracketIndex))
        dismiss()
        delegate.autocomplete(self, didCommit: tag, replacingRange: range)
    }

    private func updateContent() {
        let view = AutocompleteList(
            suggestions: suggestions,
            selectionIndex: selectionIndex,
            onTap: { [weak self] index in
                self?.selectionIndex = index
                self?.commitSelection()
            }
        )
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 280)
            panel?.contentView = hosting
            hostingView = hosting
        }
    }
}

private struct AutocompleteList: View {
    let suggestions: [AudioTag]
    let selectionIndex: Int
    let onTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("Audio tags")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↑↓ ↩")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, tag in
                Button {
                    onTap(idx)
                } label: {
                    HStack {
                        Text("[\(tag.label)]")
                            .font(.system(size: 12, weight: .semibold))
                        Text(tag.category)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(idx == selectionIndex ? Color.accentColor.opacity(0.2) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}
