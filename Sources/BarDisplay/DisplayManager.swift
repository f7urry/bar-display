import AppKit
import CoreGraphics

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
}

final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published var lastError: String?

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
        CGDisplayRegisterReconfigurationCallback({ _, flags, ctx in
            guard !flags.contains(.beginConfigurationFlag), let ctx else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { manager.refresh() }
        }, ctx)
        refresh()
    }

    func refresh() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        let online = Array(ids.prefix(Int(count)))

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
        displays = list.sorted { ($0.isMain ? 0 : 1, $0.id) < ($1.isMain ? 0 : 1, $1.id) }
    }

    private func makeDisplay(_ id: CGDirectDisplayID) -> Display {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        let name = screen?.localizedName ?? "Display \(id)"
        return Display(id: id, name: name,
                       isBuiltin: CGDisplayIsBuiltin(id) != 0,
                       isMain: CGDisplayIsMain(id) != 0,
                       isEnabled: CGDisplayIsActive(id) != 0 || CGDisplayIsInMirrorSet(id) != 0,
                       modes: modes(for: id),
                       currentModeID: CGDisplayCopyDisplayMode(id).map { $0.ioDisplayModeID })
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
        if !enabled { disabled[display.id] = display.name }
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
