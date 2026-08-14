import SwiftUI

/// 全系统按压微交互 scale(0.95)（spec §7.2）
struct DSPressEffect: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 主按钮：行动蓝实心药丸
struct BluePillButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(DS.actionBlue))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 次按钮：蓝描边幽灵药丸
struct GhostPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(DS.actionBlue)
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .background(Capsule().stroke(DS.actionBlue, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 工具按钮：墨色小圆角矩形
struct DarkUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 15)
            .background(RoundedRectangle(cornerRadius: 8).fill(DS.darkCard))   // 反馈⑬①:同侧签,墨底钮恒深
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 小尺寸行动蓝药丸(R17 §三共享化):详情页地点行内联「导航」钮专用紧凑尺寸
/// (BluePillButtonStyle 是大号 CTA;行前日程查看页/小本本四段详情共用本样式)
struct SmallBluePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Capsule().fill(DS.actionBlue))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 16) {
        Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
        Button("封盘") {}.buttonStyle(BluePillButtonStyle(fullWidth: true))
        Button("接受邀请") {}.buttonStyle(GhostPillButtonStyle())
        Button("编辑") {}.buttonStyle(DarkUtilityButtonStyle())
    }
    .padding()
    .background(DS.canvas)
}
