import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "id.appfuxion.BarDisplay", category: "display")

struct DisplayMode: Identifiable, Hashable {
    let id: Int32            // CGDisplayModeGetIODisplayModeID
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    var isHiDPI: Bool { pixelWidth > width }

    var label: String {
        let hz = refreshRate > 0 ? " @ \(Int(refreshRate.rounded()))Hz" : ""
        return "\(width) × \(height)\(isHiDPI ? " (HiDPI)" : "")\(hz)"
    }
}

struct Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let isEnabled: Bool
    let modes: [DisplayMode]
    let currentModeID: Int32?
    /// True while this display mirrors a virtual HiDPI display; `modes` then belong to the virtual one.
    var hiDPIVirtual = false
    /// The display that resolution changes go to (the virtual one while forced HiDPI is on).
    var modeTargetID: CGDirectDisplayID { virtualID ?? id }
    var virtualID: CGDirectDisplayID?
}

final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published var lastError: String?

    private let virtualHiDPI = VirtualHiDPI()
    private var names: [CGDirectDisplayID: String] = [:]

    /// Physical display ID -> point width, for displays the user forced to HiDPI.
    private var forcedHiDPI: [CGDirectDisplayID: Int] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: "forcedHiDPI") as? [String: Int] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UInt32(k).map { ($0, v) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0), $1) }),
                                      forKey: "forcedHiDPI")
        }
    }

    /// Displays we disabled disappear from the online list, so remember them to allow re-enabling.
    private var disabled: [CGDirectDisplayID: String] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: "disabledDisplays") as? [String: String] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UInt32(k).map { ($0, v) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0), $1) }),
                                      forKey: "disabledDisplays")
        }
    }

    init() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ id, flags, ctx in
            log.debug("display \(id, privacy: .public) reconfigured, flags \(flags.rawValue, privacy: .public), vendor \(CGDisplayVendorNumber(id), privacy: .public)")
            guard let ctx else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(ctx).takeUnretainedValue()
            // The unplugged display can still be listed as online at this point, so act on the
            // remove event itself rather than waiting for the online list to catch up.
            if flags.contains(.removeFlag) || flags.contains(.disabledFlag) {
                DispatchQueue.main.async { manager.enableBuiltinIfNoExternal(online: manager.onlineIDs().filter { $0 != id }) }
            }
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async { manager.refresh() }
        }, ctx)
        refresh()
    }

    /// No external display left while the built-in one is off: turn the built-in back on
    /// so the user is never left without a usable screen.
    /// Vendor IDs that don't belong to real hardware: none, unknown, and 'unkn'.
    private static let placeholderVendors: Set<UInt32> = [0, 0xFFFF_FFFF, 0x756E_6B6E]

    /// macOS swaps in a placeholder display (vendor 'unkn') when the last real screen goes away;
    /// it must not count as an external monitor.
    private func isPhysicalExternal(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(id) == 0 && !Self.placeholderVendors.contains(CGDisplayVendorNumber(id))
            && !virtualHiDPI.virtualIDs.contains(id)
    }

    private func enableBuiltinIfNoExternal(online: [CGDirectDisplayID]) {
        guard !online.contains(where: isPhysicalExternal),
              let builtin = disabled.keys.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return }
        let err = SkyLight.setEnabled(true, display: builtin)
        log.notice("no external display, enabling built-in \(builtin, privacy: .public) -> CGError \(err.rawValue, privacy: .public)")
        if err == .success { disabled.removeValue(forKey: builtin) }
    }

    private func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    func refresh() {
        var online = onlineIDs()

        // A virtual HiDPI display must never outlive its monitor, or it would hold windows off-screen.
        for physical in virtualHiDPI.physicalIDs where !online.contains(physical) {
            virtualHiDPI.stop(physical: physical)
        }
        let virtualIDs = virtualHiDPI.virtualIDs
        online.removeAll { virtualIDs.contains($0) }

        var list = online.map(makeDisplay)
        var stillDisabled = disabled
        for id in online where list.first(where: { $0.id == id })?.isEnabled == true {
            stillDisabled.removeValue(forKey: id)
        }
        for (id, name) in stillDisabled where !online.contains(id) {
            list.append(Display(id: id, name: name, isBuiltin: false, isMain: false,
                                isEnabled: false, modes: [], currentModeID: nil))
        }
        disabled = stillDisabled

        enableBuiltinIfNoExternal(online: online)
        restoreForcedHiDPI(list)

        displays = list.sorted { ($0.isMain ? 0 : 1, $0.id) < ($1.isMain ? 0 : 1, $1.id) }
    }

    private func makeDisplay(_ id: CGDirectDisplayID) -> Display {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        // A mirrored display has no NSScreen of its own, so keep the last name we saw.
        if let screenName = screen?.localizedName, virtualHiDPI.virtualID(for: id) == nil { names[id] = screenName }
        let name = names[id] ?? "Display \(id)"
        let vid = virtualHiDPI.virtualID(for: id)
        let modeSource = vid ?? id
        var display = Display(id: id, name: name,
                              isBuiltin: CGDisplayIsBuiltin(id) != 0,
                              isMain: CGDisplayIsMain(modeSource) != 0,
                              isEnabled: CGDisplayIsActive(id) != 0 || CGDisplayIsInMirrorSet(id) != 0,
                              modes: modes(for: modeSource).filter { vid == nil || $0.isHiDPI },
                              currentModeID: CGDisplayCopyDisplayMode(modeSource).map { $0.ioDisplayModeID })
        display.hiDPIVirtual = vid != nil
        display.virtualID = vid
        return display
    }

    /// Re-creates forced HiDPI for monitors that come back (app launch, re-plug, re-enable).
    private func restoreForcedHiDPI(_ list: [Display]) {
        let active = virtualHiDPI.physicalIDs
        for (id, width) in forcedHiDPI where !active.contains(id) {
            guard let display = list.first(where: { $0.id == id && $0.isEnabled }) else { continue }
            startVirtualHiDPI(display, width: width)
        }
    }

    private func startVirtualHiDPI(_ display: Display, width: Int?) {
        virtualHiDPI.start(physical: display.id, name: display.name, preferredWidth: width) { [weak self] err in
            guard let self else { return }
            if err != .success { self.forcedHiDPI.removeValue(forKey: display.id) }
            self.report(err, "force HiDPI")
            self.refresh()
        }
    }

    /// Turns forced (virtual display) HiDPI on or off for a display macOS has no HiDPI mode for.
    func setForcedHiDPI(_ on: Bool, for display: Display) {
        if on {
            let width = display.modes.first { $0.id == display.currentModeID }?.width
            forcedHiDPI[display.id] = width ?? 0
            startVirtualHiDPI(display, width: width)
        } else {
            forcedHiDPI.removeValue(forKey: display.id)
            virtualHiDPI.stop(physical: display.id)
            refresh()
        }
    }

    private func modes(for id: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [] }
        var seen = Set<String>()
        return raw.filter { $0.isUsableForDesktopGUI() }
            .map { DisplayMode(id: $0.ioDisplayModeID, width: $0.width, height: $0.height,
                               pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                               refreshRate: $0.refreshRate) }
            .sorted { ($0.width, $0.isHiDPI ? 1 : 0, $0.refreshRate) > ($1.width, $1.isHiDPI ? 1 : 0, $1.refreshRate) }
            .filter { seen.insert("\($0.width)x\($0.height)-\($0.isHiDPI)-\(Int($0.refreshRate))").inserted }
    }

    func setMode(_ mode: DisplayMode, for id: CGDirectDisplayID) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode],
              let target = modes.first(where: { $0.ioDisplayModeID == mode.id }) else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        let err = CGConfigureDisplayWithDisplayMode(config, id, target, nil)
        if err == .success {
            report(CGCompleteDisplayConfiguration(config, .permanently), "change resolution")
            if let physical = virtualHiDPI.physicalIDs.first(where: { virtualHiDPI.virtualID(for: $0) == id }) {
                forcedHiDPI[physical] = mode.width
            }
        } else {
            CGCancelDisplayConfiguration(config)
            report(err, "change resolution")
        }
    }

    func setEnabled(_ enabled: Bool, for display: Display) {
        if !enabled && displays.filter(\.isEnabled).count <= 1 {
            lastError = "Can't disconnect the last active display."
            return
        }
        if !enabled {
            disabled[display.id] = display.name
            virtualHiDPI.stop(physical: display.id)
        }
        let err = SkyLight.setEnabled(enabled, display: display.id)
        report(err, enabled ? "connect display" : "disconnect display")
        if enabled && err == .success { disabled.removeValue(forKey: display.id) }
        if !enabled && err != .success { disabled.removeValue(forKey: display.id) }
        refresh()
    }

    private func report(_ err: CGError, _ action: String) {
        lastError = err == .success ? nil : "Failed to \(action) (CGError \(err.rawValue))."
    }
}
