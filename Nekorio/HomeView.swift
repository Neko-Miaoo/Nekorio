import SwiftUI

struct HomeView: View {
    let openCheckIn: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: openCheckIn) {
                        Label("自律打卡", systemImage: "calendar.badge.checkmark")
                    }
                } header: {
                    Text("个人工具箱")
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}
