import SwiftUI

/// PolyPanel — fully native SwiftUI control panel (Polymarket-style dark UI).
/// Window app + menu-bar extra; auto-starts the FastAPI backend and polls it.
@main
struct PolyPanelApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        // WindowGroup (not Window): reopens on Dock click, which matters when
        // the menu-bar extra is hidden by a crowded menu bar
        WindowGroup("Polymarket Control Panel", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Text(store.menuSummary)
        }
        .menuBarExtraStyle(.window)
    }
}
