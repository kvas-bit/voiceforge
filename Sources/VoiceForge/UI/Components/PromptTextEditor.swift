import AppKit
import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

/// Multiline script editor with inline chip highlighting for `[audio tags]`
/// and a floating autocomplete panel triggered when the user types `[`.
struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let pendingInsertion: String
    let insertTrigger: Int
    var accessibilityIdentifier: String = "sourceTextEditor"

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15, weight: .medium)
        textView.textColor = NSColor.labelColor
        textView.string = text
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        context.coordinator.textView = textView
        context.coordinator.applyTagHighlighting()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyTagHighlighting()
        }

        if context.coordinator.lastInsertTrigger != insertTrigger {
            context.coordinator.lastInsertTrigger = insertTrigger
            context.coordinator.insert(pendingInsertion)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, TagAutocompleteControllerDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var lastInsertTrigger = 0
        private lazy var autocomplete = TagAutocompleteController(delegate: self)

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            applyTagHighlighting()
            refreshAutocomplete()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if autocomplete.isVisible {
                switch selector {
                case #selector(NSResponder.moveDown(_:)):
                    autocomplete.moveSelection(by: 1); return true
                case #selector(NSResponder.moveUp(_:)):
                    autocomplete.moveSelection(by: -1); return true
                case #selector(NSResponder.insertNewline(_:)),
                     #selector(NSResponder.insertTab(_:)):
                    autocomplete.commitSelection(); return true
                case #selector(NSResponder.cancelOperation(_:)):
                    autocomplete.dismiss(); return true
                default: break
                }
            }
            return false
        }

        @MainActor
        func insert(_ token: String) {
            guard !token.isEmpty, let textView else { return }
            let selectedRange = textView.selectedRange()
            textView.insertText(token, replacementRange: selectedRange)
            text = textView.string
            applyTagHighlighting()
        }

        @MainActor
        func applyTagHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            let baseFont = NSFont.systemFont(ofSize: 15, weight: .medium)
            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            let pattern = "\\[[^\\]\\n]+\\]"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let chipFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
                regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
                    guard let range = match?.range else { return }
                    storage.addAttributes([
                        .font: chipFont,
                        .foregroundColor: NSColor.controlAccentColor,
                        .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.15)
                    ], range: range)
                }
            }
            storage.endEditing()
        }

        @MainActor
        func refreshAutocomplete() {
            guard let textView else { return }
            let caret = textView.selectedRange().location
            let nsString = textView.string as NSString
            guard caret > 0, caret <= nsString.length else {
                autocomplete.dismiss()
                return
            }

            // Find the most recent `[` before the caret with no `]` between.
            var i = caret - 1
            var partial = ""
            var foundBracket = false
            while i >= 0 {
                let ch = nsString.character(at: i)
                if ch == 0x5D { // ]
                    break
                }
                if ch == 0x5B { // [
                    foundBracket = true
                    break
                }
                if let scalar = Unicode.Scalar(ch) {
                    partial = String(scalar) + partial
                }
                i -= 1
            }

            if foundBracket {
                let rect = caretScreenRect()
                autocomplete.show(at: rect, query: partial, bracketIndex: i, caretIndex: caret)
            } else {
                autocomplete.dismiss()
            }
        }

        @MainActor
        private func caretScreenRect() -> NSRect {
            guard let textView, let window = textView.window else { return .zero }
            let caret = textView.selectedRange()
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            guard let layoutManager, let textContainer else { return .zero }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: caret, actualCharacterRange: nil)
            let rectInContainer = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let rectInView = rectInContainer.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let rectInWindow = textView.convert(rectInView, to: nil)
            return window.convertToScreen(rectInWindow)
        }

        // MARK: - TagAutocompleteControllerDelegate

        @MainActor
        func autocomplete(_ controller: TagAutocompleteController, didCommit tag: AudioTag, replacingRange: NSRange) {
            guard let textView else { return }
            // replacingRange covers `[` through caret; replace with `[label] `.
            let replacement = "[\(tag.label)] "
            if textView.shouldChangeText(in: replacingRange, replacementString: replacement) {
                textView.textStorage?.replaceCharacters(in: replacingRange, with: replacement)
                textView.didChangeText()
                let newCaret = replacingRange.location + (replacement as NSString).length
                textView.setSelectedRange(NSRange(location: newCaret, length: 0))
                text = textView.string
                applyTagHighlighting()
            }
        }
    }
}
