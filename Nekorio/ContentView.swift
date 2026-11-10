import SwiftUI

struct ContentView: View {
    private enum Destination: Hashable {
        case checkIn
        case home
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var destination: Destination = .home

    var body: some View {
        TabView(selection: $destination) {
            Tab("打卡", systemImage: "calendar.badge.checkmark", value: Destination.checkIn) {
                CheckInView()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
            }

            Tab("Home", systemImage: "house", value: Destination.home) {
                HomeView {
                    destination = .checkIn
                }
                .environment(\.horizontalSizeClass, horizontalSizeClass)
            }
        }
        // Keep the system tab bar at the bottom on regular-width devices.
        .environment(\.horizontalSizeClass, .compact)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CheckInStore())
            .tint(AppTheme.lightPink.color)
    }
}
#endif
