import Foundation
import ObjectiveC

/// SwiftPM resource bundles in the shipped app (#92).
///
/// SwiftPM's generated `Bundle.module` for a dependency (KeyboardShortcuts) looks only at
/// `ScreenCap.app/<Name>.bundle`, then at the build machine's absolute `.build` path. codesign
/// refuses anything in the app root, so bundle.sh puts those bundles in `Contents/Resources` and
/// this redirects the root lookup there. Without it Settings ▸ Shortcuts traps on any other Mac.
enum ResourceBundles {
    /// Where `requested` should really load from, or nil to leave it alone. Only a missing
    /// `<app>/<Name>.bundle` with a twin in `Contents/Resources` is redirected.
    static func redirect(_ requested: String, appPath: String, resourcesPath: String,
                         exists: (String) -> Bool) -> String? {
        let url = URL(fileURLWithPath: requested)
        guard url.pathExtension == "bundle",
              url.deletingLastPathComponent().standardizedFileURL.path
                == URL(fileURLWithPath: appPath).standardizedFileURL.path,
              !exists(requested) else { return nil }
        let candidate = URL(fileURLWithPath: resourcesPath).appendingPathComponent(url.lastPathComponent).path
        return exists(candidate) ? candidate : nil
    }

    private typealias InitWithPath = @convention(c) (Unmanaged<AnyObject>, Selector, NSString?) -> Unmanaged<AnyObject>?
    nonisolated(unsafe) private static var original: InitWithPath?

    /// Wraps `-[NSBundle initWithPath:]` once, at launch before anything touches `Bundle.module`.
    /// Only redirects when running from an .app (not `swift run`). Nonisolated: bundles load on any thread.
    static func install() {
        guard original == nil, Bundle.main.bundlePath.hasSuffix(".app"),
              let resources = Bundle.main.resourcePath,
              let method = class_getInstanceMethod(Bundle.self, NSSelectorFromString("initWithPath:")) else { return }
        let appPath = Bundle.main.bundlePath
        let forward = unsafeBitCast(method_getImplementation(method), to: InitWithPath.self)
        let selector = NSSelectorFromString("initWithPath:")
        original = forward
        // Unmanaged passes self (consumed) and the result (+1) straight through, matching init ARC rules.
        let replacement: @convention(block) (Unmanaged<AnyObject>, NSString?) -> Unmanaged<AnyObject>? = { obj, path in
            let fixed = path.flatMap {
                redirect($0 as String, appPath: appPath, resourcesPath: resources,
                         exists: { FileManager.default.fileExists(atPath: $0) })
            }
            return forward(obj, selector, fixed.map { $0 as NSString } ?? path)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}
