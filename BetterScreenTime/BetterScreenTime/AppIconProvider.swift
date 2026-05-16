import AppKit
import Foundation

enum AppIconProvider {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()
    private static var missingBundleIds: Set<String> = []

    static func icon(for bundleId: String) -> NSImage? {
        guard !bundleId.isEmpty else { return nil }
        if let cached = cache.object(forKey: bundleId as NSString) { return cached }
        if missingBundleIds.contains(bundleId) { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            missingBundleIds.insert(bundleId)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: bundleId as NSString)
        return icon
    }
}
