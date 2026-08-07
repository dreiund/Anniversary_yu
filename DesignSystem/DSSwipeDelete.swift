import SwiftUI

/// 卡片左滑删除：系统 swipeActions 的通高方角红条与圆角卡片不搭，改为自绘——
/// 卡片左移露出同高圆角红按钮（淡入 + 微缩放），松手过半程吸附展开，否则弹回。
/// `openID` 由列表持有，保证同时只开一行；滑新行/点卡片/点删除都会收起。
struct SwipeDeleteRow<ID: Equatable, Content: View>: View {
    let id: ID
    @Binding var openID: ID?
    var buttonWidth: CGFloat = 68
    var cornerRadius: CGFloat = DS.Radius.card
    var buttonInset: CGFloat = 0      // 行内紧凑样式：按钮上下内缩
    var showsLabel = true             // 矮行（如行前日程）只放图标
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    // 手势取消（如被竖向滚动抢走）时自动归零并带回弹动画，避免卡片停在半路
    @GestureState(resetTransaction: Transaction(animation: .snappy))
    private var drag: CGFloat = 0

    private let gap: CGFloat = 8
    private var revealed: CGFloat { buttonWidth + gap }
    private var isOpen: Bool { openID == id }

    /// 卡片位移 = 静止位 + 手势位移；超出露出量走 1/3 橡皮筋，向右不越 0
    private var offset: CGFloat {
        let base = (isOpen ? -revealed : 0) + drag
        if base < -revealed { return -revealed + (base + revealed) / 3 }
        return min(base, 0)
    }

    var body: some View {
        let progress = revealed > 0 ? min(1, -offset / revealed) : 0
        ZStack(alignment: .trailing) {
            // 关闭态按钮必须整个移出视图树：透明按钮仍留在无障碍树里，
            // 多行列表会积一堆隐形「删除」（VoiceOver 乱报、UI 测试匹配不唯一）
            if progress > 0 {
                Button {
                    withAnimation(.snappy) { openID = nil }
                    onDelete()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill").font(.system(size: 16))
                        if showsLabel {
                            Text("删除").font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: cornerRadius).fill(DS.dsRed))
                    .padding(.vertical, buttonInset)
                }
                .opacity(progress)
                .scaleEffect(0.85 + 0.15 * progress)
                .allowsHitTesting(isOpen)
            }

            content()
                .overlay {
                    if isOpen {   // 开着时点卡片 = 收起，不触发卡片自身的跳转
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { withAnimation(.snappy) { openID = nil } }
                    }
                }
                // 收起层必须在 offset 之前挂：offset 不改布局框，挂在其后收起层会停在
                // 卡片原位、盖住露出的删除按钮，点删除全被收起层吃掉
                .offset(x: offset)
        }
        // highPriorityGesture：压过卡片内 NavigationLink（子视图手势默认优先，普通 .gesture
        // 抢不到，横划会被按钮当点击）；竖向滚动仍归 ScrollView 的 UIKit pan，不受影响
        .highPriorityGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($drag) { value, state, _ in
                // 首次落笔竖向占优则交还滚动，不接管；一旦接管则持续跟手
                guard state != 0
                        || abs(value.translation.width) > abs(value.translation.height)
                else { return }
                if openID != nil, openID != id {
                    withAnimation(.snappy) { openID = nil }   // 滑新行时收起旧行
                }
                state = value.translation.width
            }
            .onEnded { value in
                // 用预测终点吸附：轻快一甩也能展开
                let projected = (isOpen ? -revealed : 0) + value.predictedEndTranslation.width
                withAnimation(.snappy) {
                    openID = projected < -revealed * 0.6 ? id : nil
                }
            }
    }
}
