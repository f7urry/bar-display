import CoreGraphics
import Foundation

/// Bridge to the private SkyLight call used to enable/disable (soft-disconnect) a display.
enum SkyLight {
    private typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let configureEnabled: ConfigureEnabledFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let sym = dlsym(handle, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(sym, to: ConfigureEnabledFn.self)
    }()

    static var isAvailable: Bool { configureEnabled != nil }

    @discardableResult
    static func setEnabled(_ enabled: Bool, display: CGDirectDisplayID) -> CGError {
        guard let fn = configureEnabled else { return .notImplemented }
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success else { return err }
        err = fn(config, display, enabled)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            return err
        }
        return CGCompleteDisplayConfiguration(config, .permanently)
    }
}
