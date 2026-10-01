import Foundation
#if canImport(HeraldClient)
@_exported import HeraldClient
#endif

public extension Notification.Name {
    /// Posted (on the main queue) whenever history, registry or banners change.
    static let heraldChanged = Notification.Name("com.ivg.herald.changed")
}
