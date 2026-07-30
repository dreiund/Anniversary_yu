import SwiftUI

/// 深色内容卡：一律圆角卡片留边距，禁止通栏（spec §7.2 用户修正①）
struct DarkCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.darkCard))
    }
}

struct ParchmentCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.parchment))
    }
}

/// iOS 分组列表容器（白组卡 + hairline 描边）
struct GroupedSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.canvas)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))
    }
}

struct GroupedRow: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = DS.inkMuted
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 15)).foregroundStyle(DS.ink)
                Spacer()
                if let value {
                    Text(value).font(.system(size: 14)).foregroundStyle(valueColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if showsDivider {
                DS.hairline.frame(height: 1).padding(.leading, 14)
            }
        }
    }
}

/// 底部毛玻璃栏（Tab 栏 / 计划页统计栏）
struct FrostedBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { DS.hairline.frame(height: 1) }
    }
}

#Preview {
    VStack(spacing: 16) {
        DarkCard {
            VStack(spacing: 4) {
                Text("距下次见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                Text("12 天").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                Text("查看行前计划 · 已安排 5 项 ›").font(.system(size: 13)).foregroundStyle(DS.skyBlue)
            }
        }
        ParchmentCard { Text("今日心情").dsCaption() }
        GroupedSection {
            GroupedRow(title: "配对状态", value: "已连接 ✓", valueColor: DS.dsGreen)
            GroupedRow(title: "在一起的日子", value: "2025.06.09 ›")
            GroupedRow(title: "Face ID 锁", value: "开", valueColor: DS.actionBlue, showsDivider: false)
        }
        FrostedBottomBar {
            HStack {
                Text("已安排 5 项 · 完成 2 项").dsCaption()
                Spacer()
                Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
            }
        }
    }
    .padding()
    .background(DS.parchment)
}
