import SwiftUI
import AppKit

/// Inline-editable, Finder-style title used by list rows.
///
/// A SwiftUI `Text` with `.onTapGesture(count: 2)` inside a `List` does not
/// reliably receive double clicks on macOS, because the list handles mouse
/// events itself. Backing the title with an `NSTextField` gives us native
/// click handling plus a real text editor for inline renaming.
///
/// Clicking a row selects it. Clicking the name of the already-selected row
/// starts editing right away (as in Finder); a double click also works.
struct EditableTitleField: NSViewRepresentable {
    let text: String
    let isEditing: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onBeginEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditableTitleTextField {
        let field = EditableTitleTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = false
        field.isSelectable = false
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.stringValue = text
        field.delegate = context.coordinator
        field.onSingleClick = { context.coordinator.handleClick() }
        field.onDoubleClick = { context.coordinator.handleClick() }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: EditableTitleTextField, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.isEditing {
            if !isEditing {
                context.coordinator.endEditing(commit: false)
            }
            return
        }

        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEditable = false
        field.isSelectable = false
        if isEditing {
            context.coordinator.beginEditing()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: EditableTitleField
        weak var field: EditableTitleTextField?
        private(set) var isEditing = false
        private var finished = false

        init(_ parent: EditableTitleField) {
            self.parent = parent
        }

        func handleClick() {
            guard !isEditing else { return }
            if parent.isSelected {
                parent.onBeginEdit()
                beginEditing()
            } else {
                parent.onSelect()
            }
        }

        func beginEditing() {
            guard let field, !isEditing else { return }
            isEditing = true
            finished = false
            field.isEditable = true
            field.isSelectable = true
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.isEditing else { return }
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }

        func endEditing(commit: Bool) {
            guard isEditing, !finished, let field else { return }
            finished = true
            let value = field.stringValue
            isEditing = false
            field.isEditable = false
            field.isSelectable = false
            if field.currentEditor() != nil {
                field.window?.makeFirstResponder(nil)
            }
            if commit {
                parent.onCommit(value)
            } else {
                field.stringValue = parent.text
                parent.onCancel()
            }
        }

        func cancelEditing() {
            endEditing(commit: false)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            endEditing(commit: true)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                endEditing(commit: false)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                endEditing(commit: true)
                return true
            }
            return false
        }
    }
}

final class EditableTitleTextField: NSTextField {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if isEditable {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onSingleClick?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? EditableTitleField.Coordinator)?.cancelEditing()
    }
}
