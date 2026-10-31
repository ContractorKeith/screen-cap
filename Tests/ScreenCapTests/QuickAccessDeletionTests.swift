import AppKit
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Quick Access Delete and Settings sidebar (#104, #105)")
@MainActor
struct QuickAccessDeletionTests {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    @Test func bothStepsSucceedWithoutMessage() async {
        var deleted = false
        var trashed: URL?
        let url = URL(fileURLWithPath: "/tmp/shot.png")
        let message = await QuickAccessDeletion.run(deleteRecord: { deleted = true }, fileURL: url,
                                                    trash: { trashed = $0 })
        #expect(message == nil)
        #expect(deleted)
        #expect(trashed == url)
    }

    @Test func trashFailureIsReported() async {
        let url = URL(fileURLWithPath: "/tmp/shot.png")
        let message = await QuickAccessDeletion.run(deleteRecord: nil, fileURL: url) { _ in
            throw Failure(errorDescription: "The folder is read-only.")
        }
        #expect(message == "Couldn't move shot.png to the Trash: The folder is read-only.")
    }

    @Test func historyFailureIsReportedAndFileStillTrashed() async {
        var trashed = false
        let message = await QuickAccessDeletion.run(
            deleteRecord: { throw Failure(errorDescription: "Disk full.") },
            fileURL: URL(fileURLWithPath: "/tmp/shot.png"),
            trash: { _ in trashed = true }
        )
        #expect(message == "Couldn't remove from history: Disk full.")
        #expect(trashed)
    }

    @Test func realTrashOfMissingFileFails() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString).png")
        let message = await QuickAccessDeletion.run(deleteRecord: nil, fileURL: missing) {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
        #expect(message?.hasPrefix("Couldn't move \(missing.lastPathComponent) to the Trash") == true)
    }

    @Test func nothingToDoIsSilent() async {
        #expect(await QuickAccessDeletion.run(deleteRecord: nil, fileURL: nil) { _ in } == nil)
    }

    /// Every sidebar title fits beside its icon at the system font, so none truncates.
    @Test func settingsTitlesFitTheSidebar() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let iconAndInsets: CGFloat = 60
        for tab in AutomationCommand.SettingsTab.allCases {
            let width = (tab.title as NSString).size(withAttributes: [.font: font]).width
            #expect(width + iconAndInsets <= SettingsView.sidebarWidth, "\(tab.title) is \(width) pt")
        }
        let titles = AutomationCommand.SettingsTab.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }
}
