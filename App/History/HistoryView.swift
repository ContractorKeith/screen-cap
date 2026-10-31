import AppKit
import ScreenCapKit
import SwiftUI

/// Grid of recent captures with a kind filter, search, actions and a storage footer.
struct HistoryView: View {
    @Bindable var model: HistoryViewModel
    let actions: HistoryActions
    @State private var confirmingDelete = false

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search text, app or window")
        .toolbar { toolbar }
        .onDeleteCommand { if !model.selection.isEmpty { confirmingDelete = true } }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { actions.delete(model.selection) }
        } message: {
            Text("The files are removed from history. Saved copies elsewhere are kept.")
        }
    }

    @ViewBuilder private var content: some View {
        let records = model.visible
        if !model.isAvailable {
            placeholder("History is unavailable", "The history folder couldn't be opened.")
        } else if records.isEmpty {
            placeholder(model.records.isEmpty ? "No captures yet" : "No matches",
                        model.records.isEmpty ? "Captures from the last \(retentionText) show up here."
                                              : "Try another search or filter.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(records) { record in
                        HistoryCell(record: record, isSelected: model.selection.contains(record.id))
                            .onTapGesture(count: 2) { actions.openInEditor(record) }
                            .onTapGesture {
                                let toggling = NSEvent.modifierFlags.contains(.command)
                                model.selection = HistoryViewModel.select(record.id, in: model.selection,
                                                                          toggling: toggling)
                            }
                            .contextMenu { contextMenu(for: record) }
                    }
                }
                .padding(14)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private func placeholder(_ title: String, _ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.title3)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            let size = ByteCountFormatter.string(fromByteCount: model.storageBytes, countStyle: .file)
            Text("\(model.visible.count) captures · \(size)")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Keeps \(retentionText)").foregroundStyle(.secondary)
            Button("Purge Now") { actions.purge() }
                .help("Delete captures older than \(retentionText)")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Kind", selection: $model.kindFilter) {
                Text("All").tag(HistoryKind?.none)
                Divider()
                ForEach(HistoryViewModel.filterKinds, id: \.self) { kind in
                    Text(HistoryViewModel.title(for: kind)).tag(HistoryKind?.some(kind))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            let selected = model.selectedRecords
            Button { selected.first.map(actions.openInEditor) } label: {
                Label("Open in Editor", systemImage: "pencil.and.outline")
            }
            .disabled(selected.count != 1)
            Button { actions.copy(selected) } label: { Label("Copy", systemImage: "doc.on.doc") }
                .disabled(selected.isEmpty)
            Button { selected.first.map(actions.saveAs) } label: {
                Label("Save As…", systemImage: "square.and.arrow.down")
            }
            .disabled(selected.count != 1)
            Button { actions.reveal(selected) } label: { Label("Reveal in Finder", systemImage: "folder") }
                .disabled(selected.isEmpty)
            Button { actions.restore(model.selection) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canRestore)
            .help("Show closed captures in Quick Access again")
            Button { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                .disabled(selected.isEmpty)
        }
    }

    @ViewBuilder private func contextMenu(for record: CaptureRecord) -> some View {
        let targets = model.selection.contains(record.id) ? model.selectedRecords : [record]
        Button("Open in Editor") { actions.openInEditor(record) }
        Button("Copy") { actions.copy(targets) }
        Button("Save As…") { actions.saveAs(record) }
        Button("Reveal in Finder") { actions.reveal(targets) }
        if HistoryViewModel.canRestore(targets) {
            Button("Restore to Quick Access") { actions.restore(Set(targets.map(\.id))) }
        }
        Divider()
        Button("Delete", role: .destructive) { actions.delete(Set(targets.map(\.id))) }
    }

    private var deleteTitle: String {
        model.selection.count == 1 ? "Delete this capture?" : "Delete \(model.selection.count) captures?"
    }

    private var retentionText: String {
        let days = actions.settings.historyRetentionDays
        return days == 1 ? "1 day" : "\(days) days"
    }
}

/// One thumbnail with its kind badge, date and app.
private struct HistoryCell: View {
    let record: CaptureRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                thumbnail
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(HistoryViewModel.title(for: record.kind))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(6)
                if record.closedAt != nil {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help("Closed from Quick Access")
                }
            }
            Text(record.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
            Text(record.appName ?? record.windowTitle ?? "\(record.pixelWidth) × \(record.pixelHeight)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.accentColor.opacity(0.25) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = ThumbnailCache.image(at: record.thumbnailURL) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary)
        }
    }
}

/// Thumbnails are small and immutable per record, so decoded images are cached by URL.
@MainActor
private enum ThumbnailCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
