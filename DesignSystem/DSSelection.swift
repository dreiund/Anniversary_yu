import SwiftUI

/// 批量管理模式的选择圈（◉/○），列表卡片左侧；备忘 chip 等小件用小号
struct SelectionCircle: View {
    let isOn: Bool
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size))
            .foregroundStyle(isOn ? DS.actionBlue : DS.chipBorder)
            .animation(.snappy, value: isOn)
    }
}

/// 管理模式底栏内容：已选计数 + 删除所选（红字，空选禁用）。宿主自行包 FrostedBottomBar/safeAreaInset。
struct BatchDeleteBar: View {
    let count: Int
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("已选 \(count) 项").dsCaption()
            Spacer()
            Button("删除所选", action: onDelete)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(count == 0 ? DS.inkMuted : DS.dsRed)
                .disabled(count == 0)
                .buttonStyle(DSPressEffect())
        }
    }
}
