import Foundation

/// App-wide constants shared by the app shell and tests.
public enum ScreenCapKit {
    /// Marketing version. Keep in sync with CFBundleShortVersionString in App/Resources/Info.plist.
    public static let version = "0.1.0"
    public static let bundleIdentifier = "com.contractorkeith.screencap"
    public static let urlScheme = "screencap"
    public static let repositoryURL = URL(string: "https://github.com/ContractorKeith/screen-cap")!
    public static let licenseURL = URL(string: "https://github.com/ContractorKeith/screen-cap/blob/main/LICENSE")!
    public static let licenseName = "MIT License"
}
