import CGVirtualDisplayPrivate
import CoreGraphics
import Foundation
import os

private let log = Logger(subsystem: "id.appfuxion.BarDisplay", category: "virtual-hidpi")

/// Forces HiDPI on a display that macOS doesn't offer it for (e.g. 1920 × 1080 on a 1080p monitor).
/// Creates a virtual display with 2× modes and makes the real display mirror it, so macOS draws at
/// 3840 × 2160 and scales it down to the panel. Releasing the virtual display ends the mirror, so
/// quitting the app always restores the monitor.
final class VirtualHiDPI {
    /// Physical display ID -> its virtual HiDPI display.
    private var sessions: [CGDirectDisplayID: CGVirtualDisplay] = [:]

    static var isAvailable: Bool { NSClassFromString("CGVirtualDisplay") != nil }

    var physicalIDs: Set<CGDirectDisplayID> { Set(sessions.keys) }
    var virtualIDs: Set<CGDirectDisplayID> { Set(sessions.values.map(\.displayID)) }
    func virtualID(for physical: CGDirectDisplayID) -> CGDirectDisplayID? { sessions[physical]?.displayID }

    /// Starts mirroring `physical` to a new virtual HiDPI display. `completion` runs on the main queue.
    func start(physical: CGDirectDisplayID, name: String, preferredWidth: Int?,
               completion: @escaping (CGError) -> Void) {
        guard Self.isAvailable else { return completion(.notImplemented) }
        guard sessions[physical] == nil else { return completion(.success) }

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let physicalModes = (CGDisplayCopyAllDisplayModes(physical, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }
        // Native panel size: the largest 1× mode (HiDPI modes have larger pixel sizes but aren't the panel's).
        guard let native = physicalModes.filter({ $0.pixelWidth == $0.width })
            .max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight })
        else { return completion(.failure) }
        let nativeW = native.pixelWidth, nativeH = native.pixelHeight
        let aspect = Double(nativeW) / Double(nativeH)

        // Offer every point size the panel supports with the native aspect ratio, each at 2× pixels.
        var sizes = Set<[Int]>([[nativeW, nativeH]])
        for m in physicalModes where m.pixelWidth == m.width && m.width >= 1024 && m.width <= nativeW
            && abs(Double(m.width) / Double(m.height) - aspect) < 0.02 {
            sizes.insert([m.width, m.height])
        }
        let refresh = CGDisplayCopyDisplayMode(physical).map(\.refreshRate).flatMap { $0 > 0 ? $0 : nil } ?? 60

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = .main
        descriptor.name = "\(name) HiDPI"
        descriptor.maxPixelsWide = UInt32(nativeW * 2)
        descriptor.maxPixelsHigh = UInt32(nativeH * 2)
        let mm = CGDisplayScreenSize(physical)
        descriptor.sizeInMillimeters = mm.width > 0 ? mm : CGSize(width: 527, height: 296)
        descriptor.vendorID = 0x4244 // "BD"
        descriptor.productID = CGDisplayModelNumber(physical)
        descriptor.serialNum = CGDisplaySerialNumber(physical) ^ physical

        guard let virtual = CGVirtualDisplay(descriptor: descriptor) else { return completion(.failure) }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // macOS only marks a 2× mode usable when the same size is also listed at 1×, so add both.
        let sorted = sizes.sorted { $0[0] > $1[0] }
        settings.modes = sorted.map {
            CGVirtualDisplayMode(width: UInt($0[0] * 2), height: UInt($0[1] * 2), refreshRate: refresh)
        } + sorted.map {
            CGVirtualDisplayMode(width: UInt($0[0]), height: UInt($0[1]), refreshRate: refresh)
        }
        guard virtual.apply(settings) else { return completion(.failure) }
        sessions[physical] = virtual
        log.notice("created virtual \(virtual.displayID, privacy: .public) for \(physical, privacy: .public)")

        // The virtual display takes a moment to come online before it can be configured.
        let width = preferredWidth.flatMap { w in sizes.contains { $0[0] == w } ? w : nil } ?? nativeW
        attachMirror(physical: physical, width: width, attempt: 0, completion: completion)
    }

    private func attachMirror(physical: CGDirectDisplayID, width: Int, attempt: Int,
                              completion: @escaping (CGError) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard let vid = sessions[physical]?.displayID else { return completion(.failure) }
            let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let mode = (CGDisplayCopyAllDisplayModes(vid, options) as? [CGDisplayMode])?
                .first { $0.width == width && $0.pixelWidth == width * 2 }
            guard let mode else {
                if attempt < 10 { return attachMirror(physical: physical, width: width, attempt: attempt + 1, completion: completion) }
                stop(physical: physical)
                return completion(.failure)
            }
            let origin = CGDisplayBounds(physical).origin
            var config: CGDisplayConfigRef?
            var err = CGBeginDisplayConfiguration(&config)
            guard err == .success else { stop(physical: physical); return completion(err) }
            err = CGConfigureDisplayWithDisplayMode(config, vid, mode, nil)
            if err == .success { err = CGConfigureDisplayOrigin(config, vid, Int32(origin.x), Int32(origin.y)) }
            if err == .success { err = CGConfigureDisplayMirrorOfDisplay(config, physical, vid) }
            if err == .success {
                err = CGCompleteDisplayConfiguration(config, .forSession)
            } else {
                CGCancelDisplayConfiguration(config)
            }
            log.notice("mirror \(physical, privacy: .public) -> \(vid, privacy: .public): CGError \(err.rawValue, privacy: .public)")
            if err != .success { stop(physical: physical) }
            completion(err)
        }
    }

    /// Ends the mirror and destroys the virtual display.
    func stop(physical: CGDirectDisplayID) {
        guard sessions[physical] != nil else { return }
        var config: CGDisplayConfigRef?
        if CGDisplayIsOnline(physical) != 0, CGBeginDisplayConfiguration(&config) == .success {
            CGConfigureDisplayMirrorOfDisplay(config, physical, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        sessions.removeValue(forKey: physical)
        log.notice("destroyed virtual display for \(physical, privacy: .public)")
    }
}
