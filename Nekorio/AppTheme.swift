import SwiftUI

struct AppTheme: Codable, Equatable {
    static let lightPink = Self(hue: 0.96, saturation: 0.30, brightness: 0.96)

    var hue: Double
    var saturation: Double
    var brightness: Double

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

struct AppThemePreference: Codable, Equatable {
    let theme: AppTheme
    let modifiedAt: Date
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.lightPink
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
