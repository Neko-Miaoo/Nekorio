import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var checkInStore: CheckInStore

    var body: some View {
        Form {
            Section("外观") {
                NavigationLink {
                    ThemeSettingsView(theme: checkInStore.theme)
                } label: {
                    HStack {
                        Text("主题色")
                        Spacer()
                        Circle()
                            .fill(checkInStore.theme.color)
                            .overlay { Circle().strokeBorder(.quaternary, lineWidth: 1) }
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    }
                }
            }

            BackupSettingsSection()

            Section("关于") {
                LabeledContent("应用名称", value: "Nekorio")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeSettingsView: View {
    @EnvironmentObject private var checkInStore: CheckInStore
    @State var theme: AppTheme
    @State private var saveFailed = false
    @State private var showingPalette = false

    private let presets: [(name: String, color: AppTheme)] = [
        ("淡粉", .lightPink),
        ("红", AppTheme(hue: 0.01, saturation: 0.77, brightness: 0.85)),
        ("橙", AppTheme(hue: 0.08, saturation: 0.85, brightness: 0.90)),
        ("黄", AppTheme(hue: 0.13, saturation: 0.82, brightness: 0.82)),
        ("绿", AppTheme(hue: 0.36, saturation: 0.64, brightness: 0.63)),
        ("青", AppTheme(hue: 0.48, saturation: 0.72, brightness: 0.66)),
        ("蓝", AppTheme(hue: 0.59, saturation: 0.76, brightness: 0.87)),
        ("紫", AppTheme(hue: 0.76, saturation: 0.62, brightness: 0.77))
    ]

    var body: some View {
        Form {
            Section("常见色") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 8)], spacing: 12) {
                    ForEach(presets.indices, id: \.self) { index in
                        let preset = presets[index]
                        Button { theme = preset.color } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(preset.color.color)
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        if theme == preset.color {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                                Text(preset.name).font(.caption).foregroundStyle(.primary)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityAddTraits(theme == preset.color ? .isSelected : [])
                    }
                }
                .buttonStyle(.plain)
                Button { showingPalette = true } label: {
                    HStack {
                        Circle()
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 24, height: 24)
                        Text("自定义色盘")
                    }
                }
            }
            Section("预览") {
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.color)
                    .frame(height: 64)
                    .accessibilityLabel("主题色预览")
            }
            Section {
                Button("恢复默认淡粉色") { theme = .lightPink }
                Button("应用主题色") {
                    saveFailed = !checkInStore.saveTheme(theme)
                }
                .disabled(theme == checkInStore.theme)
            }
        }
        .navigationTitle("主题色")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPalette) {
            NavigationStack {
                Form {
                    ColorPicker("色盘", selection: selectedColor, supportsOpacity: false)
                    channel("色相", value: $theme.hue, display: "\(Int((theme.hue * 360).rounded()))°")
                    channel("饱和度", value: $theme.saturation, display: theme.saturation.formatted(.percent.precision(.fractionLength(0))))
                    channel("亮度", value: $theme.brightness, display: theme.brightness.formatted(.percent.precision(.fractionLength(0))))
                }
                .navigationTitle("自定义色盘")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showingPalette = false }
                    }
                }
            }
        }
        .alert("无法保存主题色", isPresented: $saveFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text(checkInStore.storageError ?? "请稍后重试。")
        }
    }

    private var selectedColor: Binding<Color> {
        Binding {
            theme.color
        } set: { color in
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else { return }
            theme = AppTheme(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness))
        }
    }

    private func channel(_ title: String, value: Binding<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent(title, value: display)
            Slider(value: value, in: 0...1) { Text(title) }
        }
    }
}
