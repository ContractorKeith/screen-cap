import AppKit
import ScreenCapKit
import SwiftUI

/// Right-hand sidebar: Style for the tool and selection, or the Background panel.
struct InspectorView: View {
    let controller: EditorWindowController
    @Bindable var model: EditorDocumentModel
    @Bindable var chrome: EditorUIState

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $chrome.panel) {
                ForEach(EditorUIState.Panel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            ScrollView {
                Group {
                    switch chrome.panel {
                    case .style: StylePanel(model: model, settings: controller.settings)
                    case .background: BackgroundPanel(model: model, preferences: controller.preferences)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(.background)
    }
}

/// Stroke, fill, shadow, opacity and the kind-specific options.
struct StylePanel: View {
    @Bindable var model: EditorDocumentModel
    @Bindable var settings: AppSettings

    /// Style shown: the first selected object's, else the tool's.
    private var style: Annotation.Style { model.selectedAnnotations.first?.style ?? model.options.style }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ColorSection(title: "Stroke", color: style.strokeColor, palette: $settings.colorPalette) { color in
                model.updateStyle(groupKey: "stroke-color") { $0.strokeColor = color }
            }
            fillSection
            LabeledSlider(title: "Stroke width", value: style.strokeWidth, range: 1...40,
                          format: "%.0f px", done: model.endGrouping) { value in
                model.updateStyle(groupKey: "stroke-width") { $0.strokeWidth = value }
            }
            LabeledSlider(title: "Opacity", value: style.opacity * 100, range: 5...100,
                          format: "%.0f%%", done: model.endGrouping) { value in
                model.updateStyle(groupKey: "opacity") { $0.opacity = value / 100 }
            }
            Toggle("Shadow", isOn: Binding { style.shadow != nil } set: { isOn in
                model.updateStyle { $0.shadow = isOn ? Document.Shadow() : nil }
            })
            KindOptionsSection(model: model)
        }
    }

    private var fillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Fill", isOn: Binding { style.fillColor != nil } set: { isOn in
                model.updateStyle { $0.fillColor = isOn ? ($0.fillColor ?? RGBAColor.white) : nil }
            })
            if let fill = style.fillColor {
                ColorSection(title: nil, color: fill, palette: $settings.colorPalette) { color in
                    model.updateStyle(groupKey: "fill-color") { $0.fillColor = color }
                }
            }
        }
    }
}

/// Options that only apply to some kinds; each shows when the tool or selection uses it.
struct KindOptionsSection: View {
    @Bindable var model: EditorDocumentModel

    private func showing(_ tools: [EditorTool], _ matches: (Annotation.Kind) -> Bool) -> Bool {
        tools.contains(model.tool) || model.selectedAnnotations.contains { matches($0.kind) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showing([.rectangle, .filledRectangle], { if case .rectangle = $0 { true } else { false } }) {
                LabeledSlider(title: "Corner radius", value: model.options.cornerRadius, range: 0...60,
                              format: "%.0f px", done: model.endGrouping) { value in
                    model.options.cornerRadius = value
                    model.updateSelectedKinds(groupKey: "corner") { kind in
                        guard case let .rectangle(rect, filled, _) = kind else { return nil }
                        return .rectangle(rect: rect, filled: filled, cornerRadius: value)
                    }
                }
            }
            if showing([.text], { if case .text = $0 { true } else { false } }) {
                LabeledSlider(title: "Font size", value: model.options.fontSize, range: 8...160,
                              format: "%.0f pt", done: model.endGrouping) { value in
                    model.options.fontSize = value
                    model.updateSelectedKinds(groupKey: "font") { kind in
                        guard case let .text(string, preset, _, rect) = kind else { return nil }
                        return .text(string: string, preset: preset, fontSize: value, rect: rect)
                    }
                }
            }
            if showing([.blur], { if case .blur = $0 { true } else { false } }) { blurOptions }
            if showing([.pixelate], { if case .pixelate = $0 { true } else { false } }) { pixelateOptions }
            if model.tool == .spotlight {
                Picker("Spotlight shape", selection: $model.options.spotlightShape) {
                    Text("Rectangle").tag(SpotlightChoice.rect)
                    Text("Ellipse").tag(SpotlightChoice.ellipse)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var blurOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Blur", selection: Binding { model.options.blurMode } set: { mode in
                model.options.blurMode = mode
                model.updateSelectedKinds { kind in
                    guard case let .blur(rect, _, radius) = kind else { return nil }
                    return .blur(rect: rect, mode: mode, radius: radius)
                }
            }) {
                Text("Secure").tag(Annotation.BlurMode.secure)
                Text("Smooth (not for secrets)").tag(Annotation.BlurMode.smooth)
            }
            .pickerStyle(.segmented)
            .help("Secure scrambles the pixels so text can't be read back. Smooth is a cosmetic blur: "
                + "text under it can still be recovered, so don't use it on passwords or personal info.")
            Text(model.options.blurMode == .secure
                 ? "Secure: pixels are scrambled; text can't be read back."
                 : "Smooth is cosmetic. Text under it can still be read. Use Secure for sensitive info.")
                .font(.caption)
                .foregroundStyle(model.options.blurMode == .secure ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            LabeledSlider(title: "Blur radius", value: model.options.blurRadius, range: 4...60,
                          format: "%.0f", done: model.endGrouping) { value in
                model.options.blurRadius = value
                model.updateSelectedKinds(groupKey: "blur") { kind in
                    guard case let .blur(rect, mode, _) = kind else { return nil }
                    return .blur(rect: rect, mode: mode, radius: value)
                }
            }
        }
    }

    private var pixelateOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledSlider(title: "Block size", value: Double(model.options.pixelateBlockSize), range: 8...64,
                          format: "%.0f px", done: model.endGrouping) { value in
                let size = Int(value)
                model.options.pixelateBlockSize = size
                model.updateSelectedKinds(groupKey: "block") { kind in
                    guard case let .pixelate(rect, _, randomize) = kind else { return nil }
                    return .pixelate(rect: rect, blockSize: size, randomize: randomize)
                }
            }
            Toggle("Randomize blocks", isOn: Binding { model.options.pixelateRandomize } set: { isOn in
                model.options.pixelateRandomize = isOn
                model.updateSelectedKinds { kind in
                    guard case let .pixelate(rect, size, _) = kind else { return nil }
                    return .pixelate(rect: rect, blockSize: size, randomize: isOn)
                }
            })
            .help("Randomized blocks are secure: block size grows with the area and colors are scrambled. "
                + "Plain pixelate keeps exact averages and can leak large text.")
            if !model.options.pixelateRandomize {
                Text("Without randomizing, large text can still be read. Turn it on for sensitive info.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A titled slider that reports live changes and the end of a drag (to close the undo group).
struct LabeledSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let format: String
    let done: () -> Void
    let changed: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: Binding { value } set: { changed($0) }, in: range) { editing in
                if !editing { done() }
            }
            .labelsHidden()
        }
    }
}

/// Color well, screen sampler and the saved palette (editable: + adds, right-click removes).
struct ColorSection: View {
    let title: String?
    let color: RGBAColor
    @Binding var palette: [RGBAColor]
    let changed: (RGBAColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let title { Text(title).font(.callout) }
                Spacer()
                ColorPicker("Color", selection: Binding { Color(nsColor: color.nsColor) } set: {
                    changed(RGBAColor(NSColor($0)))
                }, supportsOpacity: true)
                .labelsHidden()
                Button { sample() } label: { Image(systemName: "eyedropper") }
                    .buttonStyle(.borderless)
                    .help("Pick a color from the screen")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 8), spacing: 6) {
                ForEach(Array(palette.enumerated()), id: \.offset) { index, swatch in
                    Button { changed(swatch) } label: {
                        Circle().fill(Color(nsColor: swatch.nsColor))
                            .overlay(Circle().stroke(swatch == color ? Color.accentColor : .secondary.opacity(0.4),
                                                     lineWidth: swatch == color ? 2 : 1))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Remove from Palette") { palette.remove(at: index) } }
                }
                Button { if !palette.contains(color) { palette.append(color) } } label: {
                    Image(systemName: "plus.circle").frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Add the current color to the palette")
            }
        }
    }

    private func sample() {
        NSColorSampler().show { picked in
            guard let picked else { return }
            let color = RGBAColor(picked)
            MainActor.assumeIsolated { changed(color) }
        }
    }
}
