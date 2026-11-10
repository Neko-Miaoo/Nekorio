import SwiftUI

@main
struct NekorioApp: App {
    @StateObject private var checkInStore = CheckInStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(checkInStore)
                .environment(\.appTheme, checkInStore.theme)
                .tint(checkInStore.theme.color)
        }
    }
}
