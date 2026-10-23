import SwiftUI

@main
struct HelferleinApp: App {
    @StateObject private var app = AppState()
    @StateObject private var store = ConfigStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Palette.teal)
        }
    }
}
