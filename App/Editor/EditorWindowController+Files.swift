import AppKit
import ScreenCapKit
import SwiftUI
import UniformTypeIdentifiers

// Save, export, copy, share and Save to Desktop.

extension EditorWindowController {
    static let projectType = UTType(filenameExtension: ProjectFile.fileExtension, conformingTo: .package) ?? .package

    /// ⌘S. Code that needs to know when the save finishes calls `performSave(completion:)`.
    @objc func saveDocument(_ sender: Any?) {
        performSave(completion: nil)
    }

    /// Writes the `.screencap` package in place, or asks where the first time. `completion` gets
    /// true once the project is written, false if the user cancels or the write fails.
    /// Named apart from `saveDocument(_:)` on purpose: `saveDocument { … }` would bind the closure
    /// to that action's `sender` and never call it (#97).
    func performSave(completion done: (@MainActor (Bool) -> Void)?) {
        canvas.commitTextEditing()
        if let url = model.fileURL {
            writeProject(to: url, then: done)
        } else {
            performSaveAs(completion: done)
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        performSaveAs(completion: nil)
    }

    private func performSaveAs(completion done: (@MainActor (Bool) -> Void)?) {
        guard let window else { done?(false); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = suggestedName() + "." + ProjectFile.fileExtension
        panel.message = "Saves an editable ScreenCap project. Use Export… for an image file."
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self else { done?(false); return }
                self.writeProject(to: url, then: done)
            }
        }
    }

    /// Resolves automatic redaction flags, asks about opaque shapes not used as redactions and the
    /// one-time bake confirmation, then writes. Each sheet re-enters here once answered.
    private func writeProject(to url: URL, then done: (@MainActor (Bool) -> Void)?) {
        Task { @MainActor [weak self] in
            guard let self else { done?(false); return }
            await self.model.detectedTextLines()
            guard let window = self.window else { done?(false); return }
            let unmarked = self.model.unmarkedOpaqueCovers
            if !unmarked.isEmpty {
                self.warnAboutOpaqueShapes(unmarked, in: window) { [weak self] proceed in
                    if proceed { self?.writeProject(to: url, then: done) } else { done?(false) }
                }
                return
            }
            if self.model.needsRedactionBakeConfirmation() {
                self.confirmRedactionBake(in: window) { [weak self] proceed in
                    if proceed { self?.finishWrite(to: url, then: done) } else { done?(false) }
                }
                return
            }
            self.finishWrite(to: url, then: done)
        }
    }

    private func finishWrite(to url: URL, then done: (@MainActor (Bool) -> Void)?) {
        do {
            try model.saveProject(to: url)
            window?.isDocumentEdited = false
            window?.title = url.deletingPathExtension().lastPathComponent
            window?.representedURL = url
            flash("Saved")
            done?(true)
        } catch {
            present(error)
            done?(false)
        }
    }

    /// Opaque shapes that hide something on screen but aren't redactions keep the pixels beneath
    /// them in the project (#74). Offers to make them redactions, or to keep them as plain shapes.
    private func warnAboutOpaqueShapes(_ shapes: [Annotation], in window: NSWindow,
                                       then proceed: @escaping @MainActor (Bool) -> Void) {
        let names = shapes.map(\.displayName)
        let alert = NSAlert()
        alert.messageText = shapes.count == 1
            ? "This opaque shape isn’t a redaction"
            : "\(shapes.count) opaque shapes aren’t redactions"
        alert.informativeText = "\(names.joined(separator: ", ")). The project file keeps the original pixels "
            + "under them, so anyone with the file can remove the shape or open base.png and see what it covers. "
            + "Redactions are flattened into the image when you save."
        alert.addButton(withTitle: "Use as Redactions")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Keep Editable")
        let ids = Set(shapes.map(\.id))
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                switch response {
                case .alertFirstButtonReturn:
                    self?.model.setRedaction(true, for: ids)
                    proceed(true)
                case .alertThirdButtonReturn:
                    self?.model.setRedaction(false, for: ids)
                    proceed(true)
                default:
                    proceed(false)
                }
            }
        }
    }

    /// One-time sheet: saving a project flattens redactions, so they can't be edited later.
    private func confirmRedactionBake(in window: NSWindow, then proceed: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Redactions will be made permanent"
        alert.informativeText = "To keep hidden content out of the file, ScreenCap saves blur, pixelate and shapes "
            + "used as redactions (and anything beneath them) as flattened pixels. The project won't contain the "
            + "original, so these redactions can't be moved or removed after you reopen it. Other objects stay "
            + "editable. Opaque shapes not used as redactions keep the original pixels under them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { proceed(false); return }
                UserDefaults.standard.set(true, forKey: EditorDocumentModel.redactionBakeConfirmedKey)
                proceed(true)
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
    /// The name is reserved with an exclusive create, like capture saves, so it never overwrites.
    @objc func saveToDesktop(_ sender: Any?) {
        canvas.commitTextEditing()
        let options = settings.saveOptions
        do {
            let scale = min(1, Double(options.scale.factor) / max(model.document.baseImage.scale, 1))
            let format = ExportFormat(options.format, quality: options.jpegQuality)
            let data = try model.exportData(format: format, scale: scale)
            try FileManager.default.createDirectory(at: options.folder, withIntermediateDirectories: true)
            _ = try EditorFileWriter.write(data, template: options.template(), in: options.folder,
                                           context: model.filenameContext)
            flash("Saved to \(options.folder.lastPathComponent)")
        } catch {
            present(error)
        }
    }

    /// Share sheet with a temporary PNG of the render, under a reserved name so two editors
    /// sharing the same suggested name don't overwrite each other's file.
    func share(from view: NSView? = nil) {
        canvas.commitTextEditing()
        do {
            let data = try model.exportData(format: .png)
            let folder = try TempFiles.shared.makeFolder() // removed at quit (#114)
            TempFiles.shared.track(folder, owner: .token(UUID()))
            let url = try EditorFileWriter.write(data, template: EditorFileWriter.literal(suggestedName()),
                                                 in: folder)
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

/// Writes editor output under a name claimed with `FilenameTemplate.reserveUniqueURL`, the same
/// exclusive create capture saves use (#48), so a concurrent save (another process too) can't overwrite it.
enum EditorFileWriter {
    /// Reserves a free name in `folder`, writes `data` over the placeholder and returns the URL.
    /// Removes the placeholder if the write fails.
    static func write(_ data: Data, template: FilenameTemplate, in folder: URL,
                      context: FilenameTemplate.Context = .init()) throws -> URL {
        let url = try template.reserveUniqueURL(in: folder, context: context)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// A PNG template that renders `name` as typed: braces are swapped so no token expands.
    static func literal(_ name: String) -> FilenameTemplate {
        let safe = name.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
        return FilenameTemplate(safe, format: .png)
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
