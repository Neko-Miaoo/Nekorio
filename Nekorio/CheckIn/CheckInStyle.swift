import SwiftUI

enum CheckInStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemGroupedBackground)
}

extension View {
    func checkInCard(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckInStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CheckInColorMarker: View {
    var colors: [CheckInColor]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    color.tint.frame(height: proxy.size.height / Double(colors.count))
                }
            }
        }
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

struct CheckInSheetToolbar: ToolbarContent {
    let cancel: () -> Void
    var save: (() -> Void)?
    var disabled = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: cancel) {
                Label("关闭", systemImage: "chevron.down.circle")
                    .labelStyle(.iconOnly)
            }
        }
        if let save {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Label("保存", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                }
                .disabled(disabled)
            }
        }
    }
}

struct CheckInColorPicker: View {
    let title: String
    @Binding var selection: CheckInColor

    var body: some View {
        NavigationLink {
            List(CheckInColor.allCases) { color in
                Button { selection = color } label: {
                    HStack {
                        swatch(color)
                        Text(color.title)
                        Spacer()
                        if color == selection {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
            .navigationTitle(title)
        } label: {
            HStack {
                Text(title)
                Spacer()
                swatch(selection)
                Text(selection.title).foregroundStyle(.secondary)
            }
        }
    }

    private func swatch(_ color: CheckInColor) -> some View {
        Circle().fill(color.tint).frame(width: 14, height: 14).accessibilityHidden(true)
    }
}
