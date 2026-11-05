import CoreGraphics
import Foundation

/// Bridge to private SkyLight calls: enabling/disabling (soft-disconnecting) a display, and the full
/// display mode table. The public `CGDisplayCopyAllDisplayModes` hides some modes, e.g. 1920 × 1080
/// HiDPI on a 1080p monitor, that the panel can still be switched to.
enum SkyLight {
    private typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    // These three return nothing usable (displayplacer declares them void), so results are checked by value.
    private typealias NumberOfModesFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias ModeDescriptionFn = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Void
    private typealias ConfigureModeFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static let configureEnabled = symbol("CGSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)
    private static let numberOfModes = symbol("CGSGetNumberOfDisplayModes", as: NumberOfModesFn.self)
    private static let modeDescription = symbol("CGSGetDisplayModeDescriptionOfLength", as: ModeDescriptionFn.self)
    private static let configureMode = symbol("CGSConfigureDisplayMode", as: ConfigureModeFn.self)

    static var isAvailable: Bool { configureEnabled != nil }
    static var canListModes: Bool { numberOfModes != nil && modeDescription != nil && configureMode != nil }

    @discardableResult
    static func setEnabled(_ enabled: Bool, display: CGDirectDisplayID) -> CGError {
        guard let fn = configureEnabled else { return .notImplemented }
        return configure { fn($0, display, enabled) }
    }

    /// One entry of the private mode table. The mode number equals the public `ioDisplayModeID`.
    struct Mode {
        let number: Int32
        let width: Int          // points
        let height: Int
        let depth: Int
        let refreshRate: Int
        let density: Float      // 2.0 for HiDPI
    }

    /// Size and field offsets of SkyLight's mode description record, as used by displayplacer 1.4.0.
    private static let recordSize = 0xDC

    static func allModes(_ display: CGDirectDisplayID) -> [Mode] {
        guard let numberOfModes, let modeDescription else { return [] }
        var count: Int32 = 0
        numberOfModes(display, &count)
        guard count > 0, count < 10_000 else { return [] }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: recordSize, alignment: 8)
        defer { buffer.deallocate() }
        return (0..<count).compactMap { index in
            buffer.initializeMemory(as: UInt8.self, repeating: 0, count: recordSize)
            modeDescription(display, index, buffer, Int32(recordSize))
            let mode = Mode(number: Int32(bitPattern: buffer.load(fromByteOffset: 0, as: UInt32.self)),
                        width: Int(buffer.load(fromByteOffset: 8, as: UInt32.self)),
                        height: Int(buffer.load(fromByteOffset: 12, as: UInt32.self)),
                        depth: Int(buffer.load(fromByteOffset: 16, as: UInt32.self)),
                        refreshRate: Int(buffer.load(fromByteOffset: 190, as: UInt16.self)),
                        density: buffer.load(fromByteOffset: 208, as: Float.self))
            return mode.width > 0 && mode.height > 0 ? mode : nil
        }
    }

    /// Switches to a mode from `allModes` and saves it, like System Settings does.
    static func setMode(_ number: Int32, display: CGDirectDisplayID) -> CGError {
        guard let fn = configureMode else { return .notImplemented }
        return configure { fn($0, display, number); return .success }
    }

    private static func configure(_ body: (CGDisplayConfigRef?) -> CGError) -> CGError {
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success else { return err }
        err = body(config)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            return err
        }
        return CGCompleteDisplayConfiguration(config, .permanently)
    }
}
