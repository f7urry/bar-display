import SwiftUI

@main
struct BarDisplayApp: App {
    @StateObject private var manager = DisplayManager()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("BarDisplay", systemImage: "display.2") {
            MenuView(manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}
