import AppKit
import ScreenCapKit
import SwiftUI

/// Editor window content: toolbar on top, canvas in the middle, inspector on the right.
/// Colors come from system materials, so dark and light mode follow the system.
struct EditorView: View {
    let controller: EditorWindowController

    var body: some View {
        let model = controller.model
        VStack(spacing: 0) {
            if model.tool == .crop {
                CropBar(model: model)
            } else {
                EditorToolbar(controller: controller, model: model, chrome: controller.chrome)
            }
            Divider()
            HStack(spacing: 0) {
                CanvasHost(scrollView: controller.scrollView)
                    .frame(minWidth: 400, minHeight: 300)
                Divider()
                InspectorView(controller: controller, model: model, chrome: controller.chrome)
                    .frame(width: 260)
            }
        }
        .sheet(isPresented: Bindable(controller.chrome).showsTransformSheet) {
            TransformSheet(model: model) { controller.chrome.showsTransformSheet = false }
        }
    }
}

/// Wraps the canvas scroll view, which the window controller owns.
struct CanvasHost: NSViewRepresentable {
    let scrollView: NSScrollView

    func makeNSView(context: Context) -> NSScrollView { scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// Tool palette, tool presets and document actions.
struct EditorToolbar: View {
    let controller: EditorWindowController
    @Bindable var model: EditorDocumentModel
    @Bindable var chrome: EditorUIState

    var body: some View {
        HStack(spacing: 10) {
            toolButtons
            Divider().frame(height: 22)
            presetPicker
            Spacer(minLength: 8)
            if let status = chrome.status {
                Text(status).font(.callout).foregroundStyle(.secondary).transition(.opacity)
            }
            editButtons
            Divider().frame(height: 22)
            fileButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    if tool == .crop { model.beginCrop() } else { model.tool = tool }
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 24)
                        .background(model.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .help("\(tool.title) (\(tool.key.map { String($0).uppercased() } ?? ""))")
                .accessibilityLabel(A11y.toolLabel(tool))
                .accessibilityHint(A11y.toolHint(tool))
                .accessibilityValue(model.tool == tool ? A11y.selected : "")
            }
        }
    }

    /// Arrow style or text preset, shown when that tool (or such an object) is active.
    @ViewBuilder private var presetPicker: some View {
        if model.tool == .arrow || model.selectionContains({ if case .arrow = $0 { true } else { false } }) {
            Picker("Arrow", selection: arrowBinding) {
                ForEach(ArrowChoice.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 150)
            .accessibilityLabel(A11y.arrowStyle)
        } else if model.tool == .text || model.selectionContains({ if case .text = $0 { true } else { false } }) {
            Picker("Text", selection: textBinding) {
                ForEach(TextPreset.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(width: 190)
            .accessibilityLabel(A11y.textStyle)
        }
    }

    private var editButtons: some View {
        HStack(spacing: 4) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Redo (⇧⌘Z)")
            Menu {
                Button("Rotate Left") { model.rotate(clockwise: false) }
                Button("Rotate Right") { model.rotate(clockwise: true) }
                Button("Flip Horizontal") { model.flip(horizontal: true) }
                Button("Flip Vertical") { model.flip(horizontal: false) }
                Divider()
                Button("Rotate, Flip, Resize…") { chrome.showsTransformSheet = true }
                Divider()
                Button("Bring Forward") { model.arrange(.forward) }.disabled(model.selection.isEmpty)
                Button("Send Backward") { model.arrange(.backward) }.disabled(model.selection.isEmpty)
                Button("Bring to Front") { model.arrange(.front) }.disabled(model.selection.isEmpty)
                Button("Send to Back") { model.arrange(.back) }.disabled(model.selection.isEmpty)
            } label: {
                Label("Arrange", systemImage: "square.3.layers.3d")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rotate, flip, resize and arrange")
            Menu {
                Button("Zoom In") { controller.zoomIn(nil) }
                Button("Zoom Out") { controller.zoomOut(nil) }
                Button("Zoom to Fit") { controller.zoomToFit(nil) }
                Button("Actual Size") { controller.zoomToActualSize(nil) }
            } label: {
                Label("Zoom", systemImage: "plus.magnifyingglass")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Zoom (⌘+ ⌘− ⌘0 ⌘1)")
        }
    }

    private var fileButtons: some View {
        HStack(spacing: 4) {
            Button { controller.copyImage(nil) } label: { Label("Copy", systemImage: "doc.on.doc") }
                .help("Copy Image (⇧⌘C)")
            Button { controller.saveToDesktop(nil) } label: {
                Label("Save to Desktop", systemImage: "arrow.down.to.line")
            }
                .help("Save to the capture folder")
            Button { controller.saveDocument(nil) } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .help("Save Project (⌘S)")
            Button { controller.exportImage(nil) } label: { Label("Export", systemImage: "photo.badge.arrow.down") }
                .help("Export… (⌘E)")
            Button { controller.share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .help("Share")
        }
    }

    private var arrowBinding: Binding<ArrowChoice> {
        Binding {
            if case let .arrow(_, _, style)? = model.singleSelection?.kind { return ArrowChoice(style) }
            return model.options.arrow
        } set: { choice in
            model.options.arrow = choice
            model.updateSelectedKinds { kind in
                guard case let .arrow(start, end, style) = kind, ArrowChoice(style) != choice else { return nil }
                return ToolDrag.kind(for: .arrow, from: start, to: end, constrain: false,
                                     options: ToolOptions(arrow: choice))
            }
        }
    }

    private var textBinding: Binding<TextPreset> {
        Binding {
            if case let .text(_, preset, _, _)? = model.singleSelection?.kind {
                return TextPreset(rawValue: preset) ?? .plain
            }
            return model.options.textPreset
        } set: { preset in
            model.options.textPreset = preset
            model.updateSelectedKinds { kind in
                guard case let .text(string, _, size, rect) = kind else { return nil }
                return .text(string: string, preset: preset.rawValue, fontSize: size, rect: rect)
            }
        }
    }
}

/// Crop mode bar: aspect presets, custom ratio, cancel and apply.
struct CropBar: View {
    @Bindable var model: EditorDocumentModel

    var body: some View {
        HStack(spacing: 12) {
            Label("Crop", systemImage: "crop").font(.headline)
            Picker("Aspect", selection: Binding { model.cropAspect } set: { model.setCropAspect($0) }) {
                ForEach(CropAspect.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .accessibilityLabel(A11y.cropAspect)
            if model.cropAspect == .custom {
                TextField("W", value: aspectBinding(\.width), format: .number).frame(width: 44)
                    .accessibilityLabel("Aspect width")
                Text(":")
                TextField("H", value: aspectBinding(\.height), format: .number).frame(width: 44)
                    .accessibilityLabel("Aspect height")
            }
            if let rect = model.cropRect {
                Text("\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            Text("Snaps to edges · ⇧ for square").font(.caption).foregroundStyle(.secondary)
            Button("Cancel") { model.cancelCrop() }.keyboardShortcut(.cancelAction)
            Button("Apply") { model.applyCrop() }.keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func aspectBinding(_ side: WritableKeyPath<CGSize, CGFloat>) -> Binding<Double> {
        Binding { Double(model.customAspect[keyPath: side]) } set: { value in
            model.customAspect[keyPath: side] = max(value, 0.01)
            model.setCropAspect(.custom)
        }
    }
}
