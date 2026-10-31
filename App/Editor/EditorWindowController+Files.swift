import AppKit
import ScreenCapKit
import SwiftUI
import UniformTypeIdentifiers

// Save, export, copy, share and Save to Desktop.

extension EditorWindowController {
    static let projectType = UTType(filenameExtension: ProjectFile.fileExtension, conformingTo: .package) ?? .package

    @objc func saveDocument(_ sender: Any?) {
        saveDocument(sender, thenClose: false)
    }

    /// ⌘S: writes the `.screencap` package in place, or asks where the first time.
    func saveDocument(_ sender: Any?, thenClose: Bool) {
        canvas.commitTextEditing()
        if let url = model.fileURL {
            writeProject(to: url, thenClose: thenClose)
        } else {
            saveDocumentAs(sender, thenClose: thenClose)
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        saveDocumentAs(sender, thenClose: false)
    }

    private func saveDocumentAs(_ sender: Any?, thenClose: Bool) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = suggestedName() + "." + ProjectFile.fileExtension
        panel.message = "Saves an editable ScreenCap project. Use Export… for an image file."
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                self?.writeProject(to: url, thenClose: thenClose)
            }
        }
    }

    private func writeProject(to url: URL, thenClose: Bool) {
        if model.needsRedactionBakeConfirmation(), let window {
            confirmRedactionBake(in: window) { [weak self] in self?.writeProject(to: url, thenClose: thenClose) }
            return
        }
        do {
            try model.saveProject(to: url)
            window?.isDocumentEdited = false
            window?.title = url.deletingPathExtension().lastPathComponent
            flash("Saved")
            if thenClose { forceClose() }
        } catch {
            present(error)
        }
    }

    /// One-time sheet: saving a project flattens blur and pixelate, so they can't be edited later.
    private func confirmRedactionBake(in window: NSWindow, then save: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Blur and pixelate will be made permanent"
        alert.informativeText = "To keep hidden content out of the file, ScreenCap saves blurred and pixelated "
            + "areas (and anything beneath them) as flattened pixels. The project won't contain the original, "
            + "so these redactions can't be moved or removed after you reopen it. Other objects stay editable."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                UserDefaults.standard.set(true, forKey: EditorDocumentModel.redactionBakeConfirmedKey)
                save()
            }
        }
    }

    // MARK: - Export

    @objc func exportImage(_ sender: Any?) {
        guard let window else { return }
        canvas.commitTextEditing()
        let options = ExportPanelOptions(settings: settings)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName()
        panel.allowedContentTypes = [options.contentType]
        panel.isExtensionHidden = false
        let accessory = NSHostingView(rootView: ExportAccessoryView(options: options) { type in
            panel.allowedContentTypes = [type]
        })
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self else { return }
                self.writeExport(to: url, format: options.exportFormat, scale: options.scale)
            }
        }
    }

    private func writeExport(to url: URL, format: ExportFormat, scale: Double) {
        do {
            try model.exportData(format: format, scale: scale).write(to: url, options: .atomic)
            flash("Exported")
        } catch {
            present(error)
        }
    }

    /// ⇧⌘C: the rendered image as PNG on the pasteboard.
    @objc func copyImage(_ sender: Any?) {
        canvas.commitTextEditing()
        do {
            let data = try model.exportData(format: .png)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            flash("Copied")
        } catch {
            present(error)
        }
    }

    /// One-click save with the capture save folder, filename template, format and scale.
    @objc func saveToDesktop(_ sender: Any?) {
        canvas.commitTextEditing()
        let options = settings.saveOptions
        do {
            try FileManager.default.createDirectory(at: options.folder, withIntermediateDirectories: true)
            let url = options.template().uniqueURL(in: options.folder, context: model.filenameContext)
            let scale = min(1, Double(options.scale.factor) / max(model.document.baseImage.scale, 1))
            let format = ExportFormat(options.format, quality: options.jpegQuality)
            try model.exportData(format: format, scale: scale).write(to: url, options: .atomic)
            flash("Saved to \(options.folder.lastPathComponent)")
        } catch {
            present(error)
        }
    }

    /// Share sheet with a temporary PNG of the render.
    func share(from view: NSView? = nil) {
        canvas.commitTextEditing()
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenCap", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(suggestedName() + ".png")
            try model.exportData(format: .png).write(to: url, options: .atomic)
            let picker = NSSharingServicePicker(items: [url])
            let anchor = view ?? window?.contentView ?? canvas
            let rect = view == nil ? CGRect(x: anchor.bounds.maxX - 120, y: anchor.bounds.maxY - 40, width: 1,
                                            height: 1) : anchor.bounds
            picker.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
        } catch {
            present(error)
        }
    }

    func suggestedName() -> String {
        if let url = model.fileURL { return url.deletingPathExtension().lastPathComponent }
        let options = settings.saveOptions
        let file = options.template().filename(context: model.filenameContext)
        return (file as NSString).deletingPathExtension
    }
}

/// Export panel choices: format, quality and scale.
@MainActor
@Observable
final class ExportPanelOptions {
    enum Format: String, CaseIterable, Identifiable {
        case png = "PNG", jpeg = "JPEG", heic = "HEIC", tiff = "TIFF", pdf = "PDF"
        var id: String { rawValue }
    }

    var format: Format
    var quality: Double
    /// Output pixels per document pixel.
    var scale: Double = 1

    init(settings: AppSettings) {
        format = switch settings.imageFormat {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
        quality = settings.jpegQuality
    }

    var exportFormat: ExportFormat {
        switch format {
        case .png: .png
        case .jpeg: .jpeg(quality: quality)
        case .heic: .heic(quality: quality)
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }

    var contentType: UTType {
        switch format {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }

    var isLossy: Bool { format == .jpeg || format == .heic }
}

struct ExportAccessoryView: View {
    @Bindable var options: ExportPanelOptions
    var formatChanged: (UTType) -> Void

    var body: some View {
        Form {
            Picker("Format", selection: $options.format) {
                ForEach(ExportPanelOptions.Format.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Scale", selection: $options.scale) {
                Text("50%").tag(0.5)
                Text("100%").tag(1.0)
                Text("200%").tag(2.0)
            }
            if options.isLossy {
                Slider(value: $options.quality, in: 0.1...1) { Text("Quality") }
            }
        }
        .frame(width: 320)
        .padding()
        .onChange(of: options.format) { formatChanged(options.contentType) }
    }
}
