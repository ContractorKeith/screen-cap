import Foundation

/// Quick Access Delete's two steps, kept free of UI so the failure path is testable (#105):
/// remove the history record, then move the saved file (if any) to the Trash. Both run even if
/// the first fails. Returns the message for the HUD, or nil when everything worked.
enum QuickAccessDeletion {
    enum Step: Equatable { case confirm, delete }

    /// ⌫ and the Delete button ask first for a capture never saved to a file, since History's copy
    /// is then the only one (#147). A saved capture, or ⌘⌫ (`confirmed`), deletes at once.
    static func step(isSaved: Bool, confirmed: Bool) -> Step {
        isSaved || confirmed ? .delete : .confirm
    }

    @MainActor
    static func run(deleteRecord: (() async throws -> Void)?, fileURL: URL?,
                    trash: (URL) throws -> Void) async -> String? {
        var failures: [String] = []
        if let deleteRecord {
            do { try await deleteRecord() } catch {
                failures.append("Couldn't remove from history: \(error.localizedDescription)")
            }
        }
        if let fileURL {
            do { try trash(fileURL) } catch {
                let name = fileURL.lastPathComponent
                failures.append("Couldn't move \(name) to the Trash: \(error.localizedDescription)")
            }
        }
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}
