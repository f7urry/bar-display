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
                Picker("Resolution", selection: Binding(
                    get: { display.currentModeID ?? -1 },
                    set: { id in
                        if let mode = display.modes.first(where: { $0.id == id }) {
                            manager.setMode(mode, for: display.id)
                        }
                    })) {
                    let hidpi = display.modes.filter(\.isHiDPI)
                    if !hidpi.isEmpty {
                        Section("HiDPI") { ForEach(hidpi) { Text($0.label).tag($0.id) } }
                    }
                    Section("Standard") {
                        ForEach(display.modes.filter { !$0.isHiDPI }) { Text($0.label).tag($0.id) }
                    }
                }
                .labelsHidden()
            }
        }
    }
}
