import AppKit

/// Buttons under an All-In-One selection.
final class AllInOneToolbar: NSVisualEffectView {
    private let onChoose: (AllInOneChoice) -> Void

    init(onChoose: @escaping (AllInOneChoice) -> Void) {
        self.onChoose = onChoose
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 8
        let buttons = AllInOneChoice.allCases.map(makeButton)
        let stack = NSStackView(views: buttons)
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func makeButton(_ choice: AllInOneChoice) -> NSButton {
        let image = NSImage(systemSymbolName: choice.symbolName, accessibilityDescription: choice.title)
        let button = NSButton(title: choice.title, image: image ?? NSImage(), target: self, action: #selector(tapped))
        button.imagePosition = .imageAbove
        button.bezelStyle = .accessoryBarAction
        button.tag = AllInOneChoice.allCases.firstIndex(of: choice) ?? 0
        return button
    }

    @objc private func tapped(_ sender: NSButton) {
        onChoose(AllInOneChoice.allCases[sender.tag])
    }
}

/// ⌘K field for a typed W×H selection size.
final class FixedSizeField: NSVisualEffectView, NSTextFieldDelegate {
    let textField = NSTextField()
    private let onCommit: (CGSize) -> Void
    private let onCancel: () -> Void

    init(initial: CGSize?, onCommit: @escaping (CGSize) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        let label = NSTextField(labelWithString: "Size (pt):")
        textField.placeholderString = "800 × 600"
        textField.stringValue = initial.map(SelectionMath.sizeLabel) ?? ""
        textField.delegate = self
        textField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let stack = NSStackView(views: [label, textField])
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if let size = SelectionMath.parseSize(textField.stringValue) {
                onCommit(size)
            } else {
                NSSound.beep()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel()
            return true
        default:
            return false
        }
    }
}
