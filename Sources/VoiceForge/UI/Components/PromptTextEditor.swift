import AppKit
import SwiftUI

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let pendingInsertion: String
    let insertTrigger: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = scrollView.documentView as? NSTextView
        textView?.delegate = context.coordinator
        textView?.isRichText = false
        textView?.font = .systemFont(ofSize: 15, weight: .medium)
        textView?.textColor = NSColor(VoiceForgeTheme.primaryText)
        textView?.string = text
        textView?.drawsBackground = false
        textView?.isAutomaticQuoteSubstitutionEnabled = false
        textView?.isAutomaticDashSubstitutionEnabled = false
        textView?.textContainerInset = NSSize(width: 14, height: 16)
        textView?.setAccessibilityIdentifier("sourceTextEditor")
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        if context.coordinator.lastInsertTrigger != insertTrigger {
            context.coordinator.lastInsertTrigger = insertTrigger
            context.coordinator.insert(pendingInsertion)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var lastInsertTrigger = 0

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            text = textView?.string ?? ""
        }

        @MainActor
        func insert(_ token: String) {
            guard !token.isEmpty, let textView else {
                return
            }

            let selectedRange = textView.selectedRange()
            textView.insertText(token, replacementRange: selectedRange)
            text = textView.string
        }
    }
}
