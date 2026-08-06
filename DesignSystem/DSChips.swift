import SwiftUI

/// 分段/筛选 chip：选中态 = focusBlue 描边 + 蓝字（spec §7.4）
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DS.actionBlue : DS.ink)
                .lineLimit(1)
                .fixedSize()   // chip 文字永不折行；空间不足时让邻居截断

                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(DS.canvas))
                .overlay(
                    Capsule().stroke(
                        isSelected ? DS.focusBlue : DS.chipBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(DSPressEffect())
    }
}

#Preview {
    HStack {
        SelectableChip(title: "时间线", isSelected: true)
        SelectableChip(title: "路线", isSelected: false)
        SelectableChip(title: "计划", isSelected: false)
    }
    .padding()
    .background(DS.parchment)
}
