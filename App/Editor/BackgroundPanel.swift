import AppKit
import ScreenCapKit
import SwiftUI

/// Background tool (PLAN §3.3): fill, padding, corner radius, shadow, alignment, aspect ratio,
/// Auto Balance and saved presets.
struct BackgroundPanel: View {
    @Bindable var model: EditorDocumentModel
    @Bindable var preferences: EditorPreferences
    @State private var presetName = ""
    @State private var namingPreset = false

    enum FillKind: String, CaseIterable { case none = "None", solid = "Solid", gradient = "Gradient",
                                               bundled = "Built-in", custom = "Image" }

    private var background: Document.Background? { model.document.background }

    private var fillKind: FillKind {
        switch background?.fill {
        case nil: .none
        case .solid: .solid
        case .linearGradient: .gradient
        case .bundled: .bundled
        case .customImage: .custom
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Fill", selection: Binding { fillKind } set: { setFill($0) }) {
                ForEach(FillKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if let background {
                fillEditor(background.fill)
                layoutControls(background)
                Button { model.autoBalance() } label: { Label("Auto Balance", systemImage: "scale.3d") }
                    .help("Pick padding and alignment that center the content")
            }
            presetControls
        }
        .alert("Save Background Preset", isPresented: $namingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Fill

    @ViewBuilder private func fillEditor(_ fill: Document.BackgroundFill) -> some View {
        switch fill {
        case let .solid(color):
            ColorPicker("Color", selection: colorBinding(color) { .solid(color: $0) })
        case let .linearGradient(stops, angle):
            gradientEditor(stops: stops, angle: angle)
        case let .bundled(name):
            bundledGrid(selected: name)
        case .customImage:
            Button("Choose Image…") { chooseImage() }
        }
    }

    private func gradientEditor(stops: [Document.GradientStop], angle: Double) -> some View {
        let first = stops.first?.color ?? .white, last = stops.last?.color ?? .black
        return VStack(alignment: .leading, spacing: 8) {
            ColorPicker("From", selection: colorBinding(first) {
                .linearGradient(stops: Self.stops($0, last), angle: angle)
            })
            ColorPicker("To", selection: colorBinding(last) {
                .linearGradient(stops: Self.stops(first, $0), angle: angle)
            })
            LabeledSlider(title: "Angle", value: angle, range: 0...360,
                          format: "%.0f°", done: model.endGrouping) { value in
                model.updateBackground(groupKey: "bg-angle") { $0.fill = .linearGradient(stops: stops, angle: value) }
            }
        }
    }

    private func bundledGrid(selected: String) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 6), count: 3), spacing: 6) {
            ForEach(BundledBackgrounds.names, id: \.self) { name in
                Button { model.updateBackground { $0.fill = .bundled(name: name) } } label: {
                    thumbnail(name)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(name == selected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
    }

    @ViewBuilder private func thumbnail(_ name: String) -> some View {
        if let image = BundledBackgrounds.thumbnail(named: name) {
            Image(decorative: image, scale: 1).resizable().frame(width: 70, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Layout

    private func layoutControls(_ background: Document.Background) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Padding", value: background.padding, range: 0...400,
                          format: "%.0f px", done: model.endGrouping) { value in
                model.updateBackground(groupKey: "bg-padding") { $0.padding = value.rounded() }
            }
            LabeledSlider(title: "Corner radius", value: background.cornerRadius, range: 0...80,
                          format: "%.0f px", done: model.endGrouping) { value in
                model.updateBackground(groupKey: "bg-radius") { $0.cornerRadius = value.rounded() }
            }
            Toggle("Shadow", isOn: Binding { background.shadow != nil } set: { isOn in
                let shadow = Document.Shadow(radius: 24, offset: CGSize(width: 0, height: 12))
                model.updateBackground { $0.shadow = isOn ? shadow : nil }
            })
            Picker("Aspect ratio", selection: Binding { model.snapshot.backgroundAspect ?? 0 } set: { value in
                model.setBackground(background, aspect: value == 0 ? nil : value)
            }) {
                Text("Auto").tag(0.0)
                Text("1:1").tag(1.0)
                Text("4:3").tag(4.0 / 3.0)
                Text("3:2").tag(1.5)
                Text("16:9").tag(16.0 / 9.0)
                Text("9:16").tag(9.0 / 16.0)
            }
            alignmentGrid(background.alignment)
        }
    }

    private func alignmentGrid(_ current: Document.Alignment) -> some View {
        let rows: [[Document.Alignment]] = [[.topLeft, .top, .topRight], [.left, .center, .right],
                                            [.bottomLeft, .bottom, .bottomRight]]
        return HStack(alignment: .top) {
            Text("Alignment").font(.callout)
            Spacer()
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { alignment in
                            Button { model.updateBackground { $0.alignment = alignment } } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(alignment == current ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: 18, height: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Presets

    private var presetControls: some View {
        HStack {
            Menu("Presets") {
                ForEach(preferences.backgroundPresets) { preset in
                    Button(preset.name) { model.applyPreset(preset) }
                }
                if !preferences.backgroundPresets.isEmpty {
                    Divider()
                    Menu("Delete") {
                        ForEach(preferences.backgroundPresets) { preset in
                            Button(preset.name) { preferences.backgroundPresets.removeAll { $0.id == preset.id } }
                        }
                    }
                }
            }
            Button("Save…") { presetName = ""; namingPreset = true }
                .disabled(background == nil)
        }
    }

    private func savePreset() {
        guard let background else { return }
        let name = presetName.trimmingCharacters(in: .whitespaces)
        preferences.backgroundPresets.append(BackgroundPreset(
            name: name.isEmpty ? "Preset \(preferences.backgroundPresets.count + 1)" : name,
            background: background, aspect: model.snapshot.backgroundAspect
        ))
    }

    // MARK: - Helpers

    private func setFill(_ kind: FillKind) {
        switch kind {
        case .none: model.setBackground(nil, aspect: nil)
        case .solid: model.updateBackground { $0.fill = .solid(color: RGBAColor(red: 0.93, green: 0.94, blue: 0.96)) }
        case .gradient:
            model.updateBackground {
                $0.fill = .linearGradient(stops: Self.stops(RGBAColor(red: 0.42, green: 0.36, blue: 0.95),
                                                            RGBAColor(red: 0.98, green: 0.45, blue: 0.62)), angle: 45)
            }
        case .bundled: model.updateBackground { $0.fill = .bundled(name: BundledBackgrounds.names[0]) }
        case .custom: chooseImage()
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let loaded = ImageOps.load(url) else { return }
        model.setCustomBackground(loaded.image)
    }

    private func colorBinding(_ color: RGBAColor, _ fill: @escaping (RGBAColor) -> Document.BackgroundFill)
        -> Binding<Color> {
        Binding { Color(nsColor: color.nsColor) } set: { newColor in
            model.updateBackground(groupKey: "bg-color") { $0.fill = fill(RGBAColor(NSColor(newColor))) }
        }
    }

    static func stops(_ first: RGBAColor, _ last: RGBAColor) -> [Document.GradientStop] {
        [Document.GradientStop(color: first, location: 0), Document.GradientStop(color: last, location: 1)]
    }
}

/// Rotate, flip and resize dialog. Sizes are checked as they're typed against `ResizeLimits`.
struct TransformSheet: View {
    @Bindable var model: EditorDocumentModel
    let dismiss: () -> Void
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var keepAspect = true

    static let limitHint = "Up to \(ResizeLimits.maxSide) px per side, \(ResizeLimits.maxPixels / 1_000_000) MP total."

    var body: some View {
        let size = model.snapshot.imageSize
        let verdict = ResizeLimits.validate(width: ResizeLimits.parse(widthText),
                                            height: ResizeLimits.parse(heightText))
        VStack(alignment: .leading, spacing: 16) {
            Text("Rotate, Flip, Resize").font(.headline)
            HStack {
                Button("Rotate Left", systemImage: "rotate.left") { model.rotate(clockwise: false); sync() }
                Button("Rotate Right", systemImage: "rotate.right") { model.rotate(clockwise: true); sync() }
            }
            HStack {
                Button { model.flip(horizontal: true) } label: {
                    Label("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                Button { model.flip(horizontal: false) } label: {
                    Label("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                }
            }
            Divider()
            Form {
                TextField("Width (px)", text: Binding { widthText } set: { setWidth($0, size: size) })
                TextField("Height (px)", text: Binding { heightText } set: { setHeight($0, size: size) })
                Toggle("Keep aspect ratio", isOn: $keepAspect)
            }
            Text(verdict.message ?? Self.limitHint)
                .font(.caption)
                .foregroundStyle(verdict.message == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Resize") {
                    guard let target = verdict.size else { return }
                    model.resizeImage(to: target)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(verdict.size == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: sync)
    }

    private func sync() {
        widthText = ResizeLimits.text(model.snapshot.imageSize.width)
        heightText = ResizeLimits.text(model.snapshot.imageSize.height)
    }

    private func setWidth(_ text: String, size: CGSize) {
        widthText = text
        guard keepAspect, size.width > 0, let value = ResizeLimits.parse(text) else { return }
        heightText = ResizeLimits.text(value * size.height / size.width)
    }

    private func setHeight(_ text: String, size: CGSize) {
        heightText = text
        guard keepAspect, size.height > 0, let value = ResizeLimits.parse(text) else { return }
        widthText = ResizeLimits.text(value * size.width / size.height)
    }
}
