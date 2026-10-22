import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var manager: DisplayManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(manager.displays) { display in
                DisplayRow(display: display, manager: manager)
                Divider()
            }
            if let error = manager.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        manager.lastError = nil
                    } catch {
                        manager.lastError = "Launch at login failed: \(error.localizedDescription)"
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }))
            HStack {
                Button("Refresh") { manager.refresh() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

private struct DisplayRow: View {
    let display: Display
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { display.isEnabled },
                                 set: { manager.setEnabled($0, for: display) })) {
                HStack {
                    Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    Text(display.name).bold()
                    if display.isMain { Text("Main").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .toggleStyle(.switch)
            .disabled(!SkyLight.isAvailable)

            if display.isEnabled, !display.modes.isEmpty {
                let current = display.modes.first { $0.id == display.currentModeID }
                let wantsHiDPI = current?.isHiDPI ?? false

                HStack {
                Picker("Resolution", selection: Binding(
                    get: { current.map(Self.sizeKey) ?? "" },
                    set: { key in
                        if let mode = bestMode(for: key, hiDPI: wantsHiDPI, refresh: current?.refreshRate) {
                            manager.setMode(mode, for: display.id)
                        }
                    })) {
                    ForEach(sizes, id: \.self) { key in
                        Text(key.replacingOccurrences(of: "x", with: " × ")).tag(key)
                    }
                }
                .labelsHidden()

                Toggle("HiDPI", isOn: Binding(
                    get: { wantsHiDPI },
                    set: { on in
                        if let current, let mode = display.modes.first(where: {
                            Self.sizeKey($0) == Self.sizeKey(current) && $0.isHiDPI == on
                        }) {
                            manager.setMode(mode, for: display.id)
                        }
                    }))
                .toggleStyle(.switch)
                .disabled(current.map { !hasBothVariants(Self.sizeKey($0)) } ?? true)
                .help("Render the current resolution at 2× pixel density")
                .fixedSize()
                }
            }
        }
    }

    private static func sizeKey(_ mode: DisplayMode) -> String { "\(mode.width)x\(mode.height)" }

    /// Unique point resolutions, largest first.
    private var sizes: [String] {
        var seen = Set<String>()
        return display.modes.map(Self.sizeKey).filter { seen.insert($0).inserted }
    }

    private func hasBothVariants(_ key: String) -> Bool {
        let variants = Set(display.modes.filter { Self.sizeKey($0) == key }.map(\.isHiDPI))
        return variants.count == 2
    }

    /// Prefers the requested HiDPI state and refresh rate, falling back to whatever exists for that size.
    private func bestMode(for key: String, hiDPI: Bool, refresh: Double?) -> DisplayMode? {
        let candidates = display.modes.filter { Self.sizeKey($0) == key }
        let sameDensity = candidates.filter { $0.isHiDPI == hiDPI }
        let pool = sameDensity.isEmpty ? candidates : sameDensity
        return pool.first { $0.refreshRate == refresh } ?? pool.first
    }
}
