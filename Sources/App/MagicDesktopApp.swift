import SwiftUI

@main
struct MagicDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { EmptyView().frame(width: 0, height: 0).hidden() }
            .defaultSize(width: 0, height: 0)
    }
}
