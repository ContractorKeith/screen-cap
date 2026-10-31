import AppKit

/// Buttons on a Quick Access panel.
enum QuickAccessCommand: CaseIterable {
    case copy, save, annotate, pin, ocr, reveal, close, delete

    var title: String {
        switch self {
        case .copy: "Copy"
        case .save: "Save"
        case .annotate: "Annotate"
        case .pin: "Pin"
        case .ocr: "Copy Text (OCR)"
        case .reveal: "Show in Finder"
        case .close: "Close"
        case .delete: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .annotate: "pencil"
        case .pin: "pin"
        case .ocr: "text.viewfinder"
        case .reveal: "folder"
        case .close: "xmark"
        case .delete: "trash"
        }
    }
}

/// A button that works on the first click in a panel that never becomes key.
final class QuickAccessButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hover overlay: Close and Delete in the top corners, Copy and Save in the middle,
/// Annotate, Pin, OCR and Reveal along the bottom. Clicks between buttons fall through to
/// the thumbnail so a drag can start anywhere.
final class QuickAccessToolbarView: NSView {
    var onCommand: ((QuickAccessCommand) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let close = iconButton(.close)
        let delete = iconButton(.delete)
        let center = NSStackView(views: [pillButton(.copy), pillButton(.save)])
        center.spacing = 8
        let bottom = NSStackView(views: [.annotate, .pin, .ocr, .reveal].map(iconButton))
        bottom.spacing = 8
        for view in [close, delete, center, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            delete.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            center.centerXAnchor.constraint(equalTo: centerXAnchor),
            center.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottom.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Dims the thumbnail so the buttons stay readable on any capture.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        dirtyRect.fill(using: .sourceOver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    private func iconButton(_ command: QuickAccessCommand) -> NSButton {
        let image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title)
        let button = makeButton(command)
        button.image = image?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.imagePosition = .imageOnly
        button.layer?.cornerRadius = 11
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func pillButton(_ command: QuickAccessCommand) -> NSButton {
        let button = makeButton(command)
        button.attributedTitle = NSAttributedString(string: command.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ])
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        button.widthAnchor.constraint(equalToConstant: 64).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func makeButton(_ command: QuickAccessCommand) -> NSButton {
        let button = QuickAccessButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.wantsLayer = true
        button.contentTintColor = .white
        button.toolTip = command.title
        button.setAccessibilityLabel(command.title)
        button.target = self
        button.action = #selector(fire(_:))
        button.tag = QuickAccessCommand.allCases.firstIndex(of: command) ?? 0
        return button
    }

    @objc private func fire(_ sender: NSButton) {
        onCommand?(QuickAccessCommand.allCases[sender.tag])
    }
}
