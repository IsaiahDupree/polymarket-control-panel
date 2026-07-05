import SwiftUI

/// PolyPanel — thin native shell around the Polymarket-style web dashboard.
/// The single source of UI truth is backend/static/index.html served on
/// localhost; this app gives it a Dock/menu-bar presence, auto-starts the
/// backend, and shows a live balance summary in the menu bar.
@main
struct PolyPanelApp: App {
    @StateObject private var backend = BackendController()

    var body: some Scene {
        Window("Polymarket Control Panel", id: "main") {
            DashboardWebView(url: backend.dashboardURL)
                .frame(minWidth: 1080, minHeight: 700)
                .background(Color(red: 0.078, green: 0.11, blue: 0.153)) // matches --bg
                .onAppear { backend.ensureRunning() }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView().environmentObject(backend)
        } label: {
            Text(backend.menuSummary)
        }
        .menuBarExtraStyle(.window)
    }
}
