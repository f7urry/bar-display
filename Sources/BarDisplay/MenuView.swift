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
                Picker("Resolution", selection: Binding(
                    get: { current.map(Self.key) ?? "" },
                    set: { key in
                        if let mode = bestMode(for: key, refresh: current?.refreshRate) {
                            manager.setMode(mode, for: display.id)
                        }
                    })) {
                    ForEach(options, id: \.self) { key in
                        Text(Self.label(key)).tag(key)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// One entry per point size and density, e.g. "1440x810" and "1440x810@2x".
    private static func key(_ mode: DisplayMode) -> String {
        "\(mode.width)x\(mode.height)\(mode.isHiDPI ? "@2x" : "")"
    }

    private static func label(_ key: String) -> String {
        let hiDPI = key.hasSuffix("@2x")
        let size = key.replacingOccurrences(of: "@2x", with: "").replacingOccurrences(of: "x", with: " × ")
        return hiDPI ? "\(size)  HiDPI" : size
    }

    /// Unique resolutions, largest first, with the HiDPI version of a size listed before the normal one.
    private var options: [String] {
        var seen = Set<String>()
        return display.modes.map(Self.key).filter { seen.insert($0).inserted }
    }

    /// Prefers the current refresh rate, falling back to the highest one for that resolution.
    private func bestMode(for key: String, refresh: Double?) -> DisplayMode? {
        let candidates = display.modes.filter { Self.key($0) == key }
        return candidates.first { $0.refreshRate == refresh } ?? candidates.first
    }
}
