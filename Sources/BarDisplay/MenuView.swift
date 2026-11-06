import SwiftUI

private let accent = Color.orange

struct MenuView: View {
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(manager.displays) { display in
                DisplayRow(display: display, manager: manager)
            }
            if let error = manager.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            Divider()
            HStack {
                IconButton(systemName: "arrow.clockwise") { manager.refresh() }
                    .help("Refresh displays")
                Spacer()
                Menu {
                    Toggle("Launch at login", isOn: Binding(
                        get: { manager.launchAtLogin },
                        set: { manager.setLaunchAtLogin($0) }))
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(10)
        .frame(width: 250)
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        }
        .buttonStyle(.plain)
    }
}

private struct DisplayRow: View {
    let display: Display
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                Text(display.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if display.isMain {
                    Text("MAIN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 0.42, green: 0.55, blue: 0.72)))
                }
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(get: { display.isEnabled },
                                         set: { manager.setEnabled($0, for: display) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(accent)
                    .disabled(!SkyLight.isAvailable)
            }

            if display.isEnabled, !display.modes.isEmpty {
                let current = display.modes.first { $0.id == display.currentModeID }
                let wantsHiDPI = display.hiDPIVirtual || (current?.isHiDPI ?? false)
                let nativeVariant = current.map { hasBothVariants(Self.sizeKey($0)) } ?? false
                let canForce = !display.isBuiltin && VirtualHiDPI.isAvailable
                let hiDPIEnabled = display.hiDPIVirtual || nativeVariant || canForce

                HStack(spacing: 6) {
                    Picker("Resolution", selection: Binding(
                        get: { current.map(Self.sizeKey) ?? "" },
                        set: { key in
                            if let mode = bestMode(for: key, hiDPI: wantsHiDPI, refresh: current?.refreshRate) {
                                manager.setMode(mode, for: display.modeTargetID)
                            }
                        })) {
                        ForEach(sizes, id: \.self) { key in
                            Text(key.replacingOccurrences(of: "x", with: " × ")).tag(key)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                    Button {
                        setHiDPI(!wantsHiDPI, current: current, nativeVariant: nativeVariant, canForce: canForce)
                    } label: {
                        HStack(spacing: 3) {
                            if wantsHiDPI { Image(systemName: "checkmark") }
                            Text("HiDPI")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(wantsHiDPI ? Color.white : Color.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(wantsHiDPI ? accent : Color.secondary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hiDPIEnabled)
                    .opacity(hiDPIEnabled ? 1 : 0.5)
                    .help(nativeVariant || display.hiDPIVirtual
                          ? "Render the current resolution at 2× pixel density"
                          : "Force 2× rendering by mirroring this display to a virtual HiDPI display")
                    .fixedSize()
                }
            }
        }
    }

    private func setHiDPI(_ on: Bool, current: DisplayMode?, nativeVariant: Bool, canForce: Bool) {
        if display.hiDPIVirtual {
            if !on { manager.setForcedHiDPI(false, for: display) }
        } else if nativeVariant, let current, let mode = display.modes.first(where: {
            Self.sizeKey($0) == Self.sizeKey(current) && $0.isHiDPI == on
        }) {
            manager.setMode(mode, for: display.id)
        } else if on, canForce {
            manager.setForcedHiDPI(true, for: display)
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
