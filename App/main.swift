import AppKit

// Entry point: a menu-bar-only app driven by AppDelegate.
MainActor.assumeIsolated {
    ResourceBundles.install() // before any dependency touches Bundle.module (#92)
    let app = NSApplication.shared
    let delegate = AppDelegate(launch: LaunchArguments.parse(CommandLine.arguments))
    app.delegate = delegate
    app.run()
}
