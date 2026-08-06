import SwiftUI

enum PanelAction {
    case newMoment
    case mood
    case seal
    case ledgerEntry
    case quickEntry
}

struct ActionPanel: View {
    let hasOngoing: Bool
    let onAction: (PanelAction) -> Void

    private struct Tile {
        let symbol: String
        let title: String
        let action: PanelAction?
    }

    private var tiles: [Tile] {
        [
            Tile(symbol: "photo.on.rectangle", title: "记忆", action: .newMoment),
            Tile(symbol: "square.and.pencil", title: "互评", action: .ledgerEntry),
            Tile(symbol: "face.smiling", title: "心情", action: .mood),
            Tile(symbol: "heart", title: "喜怒", action: .quickEntry),
            Tile(symbol: "sparkles", title: "亲密", action: nil),
            Tile(symbol: "drop", title: "经期", action: nil),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("记一笔").dsSectionTitle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(tiles, id: \.title) { tile in
                    Button {
                        if let action = tile.action { onAction(action) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tile.symbol)
                                .font(.system(size: 18))
                                .foregroundStyle(DS.actionBlue)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(DS.canvas))
                            Text(tile.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
                    }
                    .buttonStyle(DSPressEffect())
                    .disabled(tile.action == nil)
                    .opacity(tile.action == nil ? 0.35 : 1)
                }
            }
            if hasOngoing {
                Button("封盘") { onAction(.seal) }
                    .buttonStyle(BluePillButtonStyle(fullWidth: true))
            }
            Text(hasOngoing ? "封盘：今天到此为止，晚安" : "灰色入口在后续阶段开启")
                .dsFootnote()
                .frame(maxWidth: .infinity)
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(hasOngoing ? 340 : 300)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActionPanel(hasOngoing: true) { _ in }
    }
}
