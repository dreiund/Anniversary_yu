import SwiftUI

struct PhotoViewerView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [CDPhoto]
    @State var index: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.objectID) { i, photo in
                    Group {
                        if abs(i - index) <= 1,
                           let data = photo.imageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFit()
                        } else {
                            Color.black
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(hex: 0xD2D2D7).opacity(0.64)))
            }
            .padding(DS.Spacing.md)
        }
        .overlay(alignment: .bottom) {
            Text("\(index + 1) / \(photos.count)")
                .font(.system(size: 13)).foregroundStyle(.white)
                .padding(.bottom, DS.Spacing.md)
        }
    }
}
