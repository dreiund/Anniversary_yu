import SwiftUI

let dsMoodEmojis = ["😊", "🥰", "😍", "😌", "🤣", "😴", "😢", "😡"]

struct AvatarInitial: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .fill(DS.parchment)
            .overlay(Circle().stroke(DS.hairline, lineWidth: 1))
            .overlay(
                Text(name.isEmpty ? "?" : String(name.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(DS.ink)
            )
            .frame(width: size, height: size)
    }
}

struct StarsView: View {
    let stars: Int
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(i <= stars ? DS.ink : DS.chipBorder)
            }
        }
    }
}

struct StarInputView: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    stars = i
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(i <= stars ? DS.actionBlue : DS.chipBorder)
                }
                .buttonStyle(DSPressEffect())
            }
        }
    }
}

struct EmojiPickerRow: View {
    @Binding var selection: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach(dsMoodEmojis, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.canvas))
                        .overlay(
                            Circle().stroke(
                                selection == emoji ? DS.focusBlue : DS.hairline,
                                lineWidth: selection == emoji ? 2 : 1
                            )
                        )
                }
                .buttonStyle(DSPressEffect())
            }
        }
    }
}
