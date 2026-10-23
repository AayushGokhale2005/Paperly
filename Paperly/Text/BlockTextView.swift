import SwiftUI

/// Native multiline text input retains iOS selection, dictation, autocorrection, paste,
/// and hardware-keyboard support. The document scroll view owns vertical scrolling.
struct BlockTextView: UIViewRepresentable {
    let block: TextBlock
    let focused: Bool
    let onChange: (String) -> Void
    let onFocus: () -> Void
    let onBlur: () -> Void
    let onSplit: (NSRange) -> Void
    let onDeleteEmpty: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> BlockInputView {
        let view = BlockInputView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityLabel = block.kind.title
        return view
    }
    func updateUIView(_ view: BlockInputView, context: Context) {
        view.focusRequested = focused
        view.onDeleteEmpty = onDeleteEmpty
        context.coordinator.parent = self
        if view.text != block.text, view.markedTextRange == nil {
            let range = view.selectedRange
            view.text = block.text
            view.selectedRange = NSRange(location: min(range.location, (block.text as NSString).length), length: 0)
        }
        let style: UIFont.TextStyle = block.kind == .heading1 ? .title1 : block.kind == .heading2 ? .title2 : .body
        let base = UIFont.preferredFont(forTextStyle: style)
        if block.kind == .code {
            view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
            view.autocorrectionType = .no; view.autocapitalizationType = .none
        } else {
            view.font = block.kind == .heading1 || block.kind == .heading2 ? UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: 0) : base
            view.autocorrectionType = .default; view.autocapitalizationType = .sentences
        }
        view.textColor = block.checked ? .secondaryLabel : .label
        view.accessibilityLabel = block.kind.title
        if !focused, view.isFirstResponder { view.resignFirstResponder() }
        if focused, !view.isFirstResponder, view.window != nil {
            // Dispatch past SwiftUI's update pass before changing first responder.
            DispatchQueue.main.async { [weak view] in
                guard context.coordinator.parent.focused else { return }
                view?.becomeFirstResponder()
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockInputView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, size.height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        init(_ parent: BlockTextView) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus() }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onBlur() }
        func textViewDidChange(_ textView: UITextView) { parent.onChange(textView.text) }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", parent.block.kind != .code, textView.markedTextRange == nil { parent.onSplit(range); return false }
            if text.isEmpty, range.length == 0, textView.text.isEmpty { parent.onDeleteEmpty(); return false }
            return true
        }
    }
}

final class BlockInputView: UITextView {
    var focusRequested = false
    var onDeleteEmpty: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, focusRequested {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.focusRequested else { return }
                self.becomeFirstResponder()
            }
        }
    }
    override func deleteBackward() {
        if text.isEmpty { onDeleteEmpty?() } else { super.deleteBackward() }
    }
}
