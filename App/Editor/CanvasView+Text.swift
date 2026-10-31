import AppKit
import ScreenCapKit

// In-place text editing: an NSTextView laid over the text object while it is hidden from the render.

extension CanvasView: NSTextViewDelegate {
    func beginTextEditing(_ id: UUID) {
        commitTextEditing()
        guard let annotation = model.document.annotation(withID: id),
              case let .text(string, preset, fontSize, rect) = annotation.kind else { return }
        let textPreset = TextPreset(rawValue: preset) ?? .plain
        let editor = NSTextView(frame: viewRect(rect.standardized))
        editor.string = string
        editor.font = Self.font(for: textPreset, size: fontSize)
        editor.textColor = Self.textColor(for: textPreset, style: annotation.style)
        editor.drawsBackground = true
        editor.backgroundColor = Self.editingBackground(for: textPreset, style: annotation.style)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.focusRingType = .none
        editor.delegate = self
        addSubview(editor)
        textEditor = editor
        model.editingTextID = id
        model.touch()
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
    }

    /// Writes the edited string back (growing the box to fit) and removes the overlay.
    /// An empty string deletes the object.
    func commitTextEditing() {
        guard let editor = textEditor, let id = model.editingTextID else { return }
        textEditor = nil
        let string = editor.string
        editor.removeFromSuperview()
        model.editingTextID = nil
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.selection = [id]
            model.deleteSelection()
        } else if let annotation = model.document.annotation(withID: id),
                  case let .text(_, preset, fontSize, rect) = annotation.kind {
            var used = rect.height
            if let manager = editor.layoutManager, let container = editor.textContainer {
                manager.ensureLayout(for: container)
                used = manager.usedRect(for: container).height
            }
            var fitted = rect.standardized
            fitted.size.height = max(fitted.height, used + fontSize * 0.5)
            model.setKind(id, .text(string: string, preset: preset, fontSize: fontSize, rect: fitted))
        }
        model.selection = model.document.annotation(withID: id) == nil ? [] : [id]
        model.touch()
        window?.makeFirstResponder(self)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) {
            commitTextEditing()
            return true
        }
        return false
    }

    func textDidEndEditing(_ notification: Notification) {
        commitTextEditing()
    }

    // MARK: - Text look (close to the renderer's presets)

    static func font(for preset: TextPreset, size: Double) -> NSFont {
        switch preset {
        case .plain, .outlined, .filledBackground: .systemFont(ofSize: size, weight: .semibold)
        case .monospace: .monospacedSystemFont(ofSize: size, weight: .regular)
        case .roundedLabel:
            NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.rounded)
                .flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size, weight: .semibold)
        case .boldUppercase: .systemFont(ofSize: size, weight: .heavy)
        case .handwritten: NSFont(name: "Noteworthy-Bold", size: size) ?? .systemFont(ofSize: size)
        }
    }

    private static func textColor(for preset: TextPreset, style: Annotation.Style) -> NSColor {
        switch preset {
        case .filledBackground, .roundedLabel:
            let background = style.fillColor ?? style.strokeColor
            let luminance = 0.2126 * background.red + 0.7152 * background.green + 0.0722 * background.blue
            return luminance > 0.6 ? .black : .white
        default:
            return style.strokeColor.nsColor
        }
    }

    private static func editingBackground(for preset: TextPreset, style: Annotation.Style) -> NSColor {
        switch preset {
        case .filledBackground, .roundedLabel: (style.fillColor ?? style.strokeColor).nsColor
        default: NSColor.textBackgroundColor.withAlphaComponent(0.35)
        }
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                  blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent))
    }
}
