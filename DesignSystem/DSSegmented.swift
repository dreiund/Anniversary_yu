import SwiftUI

/// R19-① 反馈修:原生 UISegmentedControl 高度固定 32pt 偏小且不可调——自绘同貌分段器。
/// 槽用系统语义色 tertiarySystemFill(与原生分段器同源,深浅色自动),滑块浅色白/深色 iOS 标准 #636366;
/// 高 42(9pt 竖内边距+15pt 字)达 44pt 热区量级,滑块 matchedGeometryEffect 弹簧滑动。
struct DSSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Namespace private var ns

    /// 滑块色:浅=纯白(原生同款);深=#636366(iOS 深色分段器标准滑块,比 DS.darkCard 亮一档才浮得出来)
    private let thumb = Color(light: 0xFFFFFF, dark: 0x636366)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 15, weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? DS.ink : DS.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(thumb)
                                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemFill)))
    }
}
