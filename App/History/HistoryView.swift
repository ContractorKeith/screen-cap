import AppKit
import QuickLook
import ScreenCapKit
import SwiftUI

/// Grid of recent captures with a kind filter, search, actions and a storage footer.
struct HistoryView: View {
    @Bindable var model: HistoryViewModel
    let actions: HistoryActions
    @State private var confirmingDelete = false
    /// Keyboard focus on the grid (#130): arrows, Return, Space, ⌘C and ⌫ work while it's set.
    @FocusState private var gridFocused: Bool
    /// Measured grid width, for how many columns ↑/↓ jump.
    @State private var gridWidth: CGFloat = 0
    /// Space shows the focused capture in Quick Look.
    @State private var previewURL: URL?

    private static let cellMinimum: CGFloat = 180
    private static let spacing: CGFloat = 14
    private let columns = [GridItem(.adaptive(minimum: cellMinimum, maximum: 260), spacing: spacing)]

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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(records) { record in cell(record) }
                    }
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear { gridWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, width in gridWidth = width }
                    })
                    .padding(14)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .focusable()
                .focused($gridFocused)
                .focusEffectDisabled()
                .defaultFocus($gridFocused, true)
                .onAppear { gridFocused = true }
                .onKeyPress(phases: .down) { press in handleKey(press, proxy: proxy) }
                .quickLookPreview($previewURL, in: model.selectedRecords.map(\.fileURL))
                .accessibilityLabel(A11y.historyGrid)
            }
        }
    }

    private func cell(_ record: CaptureRecord) -> some View {
        HistoryCell(record: record, isSelected: model.selection.contains(record.id),
                    hasFocusRing: gridFocused && model.cursor == record.id)
            .id(record.id)
            .onTapGesture(count: 2) { actions.openInEditor(record) }
            .onTapGesture {
                let toggling = NSEvent.modifierFlags.contains(.command)
                model.selection = HistoryViewModel.select(record.id, in: model.selection, toggling: toggling)
                model.cursor = record.id
                gridFocused = true
            }
            .contextMenu { contextMenu(for: record) }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(HistoryCell.label(for: record))
            .accessibilityValue(model.selection.contains(record.id) ? A11y.selected : "")
            .accessibilityHint("Double-click to open in the editor")
    }

    /// Grid keys (#130): arrows move (⇧ extends), Return opens, Space quick-looks, ⌘C copies,
    /// ⌘A selects all, ⌫ deletes after confirming. Anything else passes on (Tab moves focus).
    private func handleKey(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        if let move = Self.gridMove(press.key), !command {
            let columns = HistoryViewModel.columnCount(width: gridWidth, minimum: Self.cellMinimum,
                                                       spacing: Self.spacing)
            if let id = model.moveCursor(move, columns: columns, extending: press.modifiers.contains(.shift)) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
            }
            return .handled
        }
        if command { return handleCommandKey(press) }
        switch press.key {
        case .return: model.focusedRecord.map(actions.openInEditor)
        case .space: previewURL = previewURL == nil ? model.focusedRecord?.fileURL : nil
        case .delete, .deleteForward: if !model.selection.isEmpty { confirmingDelete = true }
        default: return .ignored
        }
        return .handled
    }

    private func handleCommandKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.option, .control, .shift]) else { return .ignored }
        switch press.key {
        case .delete, .deleteForward:
            if !model.selection.isEmpty { confirmingDelete = true }
        default:
            switch press.characters.lowercased() {
            case "c" where !model.selection.isEmpty: actions.copy(model.selectedRecords)
            case "a": model.selection = Set(model.visible.map(\.id))
            default: return .ignored
            }
        }
        return .handled
    }

    private static func gridMove(_ key: KeyEquivalent) -> HistoryViewModel.GridMove? {
        switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .above
        case .downArrow: .below
        default: nil
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
            .accessibilityLabel(A11y.historyKindFilter)
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
    /// The keyboard cursor while the grid has focus (#130).
    let hasFocusRing: Bool

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
                if let elongation {
                    Text(elongation == .tall ? "Tall" : "Wide")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: Capsule())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .help("Showing the start of a long capture; open it to see all of it")
                }
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
        .overlay {
            if hasFocusRing {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-3)
            }
        }
        .contentShape(Rectangle())
    }

    static func label(for record: CaptureRecord) -> String {
        A11y.historyThumbnail(kind: HistoryViewModel.title(for: record.kind), date: record.createdAt,
                              source: record.appName ?? record.windowTitle, closed: record.closedAt != nil)
    }

    /// Set for very tall or wide captures (scrolling), whose thumbnail shows only the start (#133).
    private var elongation: Thumbnailer.Elongation? {
        Thumbnailer.elongation(width: record.pixelWidth, height: record.pixelHeight)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = ThumbnailCache.image(at: record.thumbnailURL) {
            if let elongation {
                // Fill the cell from the top (or leading edge) so older, uncropped thumbnails of
                // long captures read the same as new cropped ones instead of a sliver.
                Color.clear
                    .overlay(alignment: elongation == .tall ? .top : .leading) {
                        Image(nsImage: image).resizable().scaledToFill()
                    }
                    .clipped()
            } else {
                Image(nsImage: image).resizable().scaledToFit()
            }
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
