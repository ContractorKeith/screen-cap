import AppKit
import ScreenCapKit
import SwiftUI

/// Version, license and project link.
struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("ScreenCap").font(.title.bold())
            Text("Version \(ScreenCapKit.version)").foregroundStyle(.secondary)
            Text("An open-source screenshot app for macOS.")
            HStack(spacing: 16) {
                Link(ScreenCapKit.licenseName, destination: ScreenCapKit.licenseURL)
                Link("GitHub", destination: ScreenCapKit.repositoryURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
