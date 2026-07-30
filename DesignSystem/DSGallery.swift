import SwiftUI

struct DSGallery: View {
    private let colors: [(String, Color)] = [
        ("canvas", DS.canvas), ("parchment", DS.parchment), ("darkCard", DS.darkCard),
        ("actionBlue", DS.actionBlue), ("focusBlue", DS.focusBlue), ("skyBlue", DS.skyBlue),
        ("ink", DS.ink), ("inkMuted", DS.inkMuted), ("hairline", DS.hairline),
        ("dsRed", DS.dsRed), ("dsGreen", DS.dsGreen), ("roseCycle", DS.roseCycle),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text("设计系统画廊").dsHero()

                Text("色彩").dsSectionTitle()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 8) {
                    ForEach(colors, id: \.0) { name, color in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: DS.Radius.image)
                                .fill(color)
                                .frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.image).stroke(DS.hairline, lineWidth: 1))
                            Text(name).dsFootnote()
                        }
                    }
                }

                Text("排版").dsSectionTitle()
                VStack(alignment: .leading, spacing: 6) {
                    Text("在一起 412 天").dsHero()
                    Text("第 1 天 · 页面标题").dsPageTitle()
                    Text("区块标题").dsSectionTitle()
                    Text("正文 17pt：排了四十分钟的队，但是值得。").dsBody()
                    Text("说明文字 14pt").dsCaption()
                    Text("脚注 12pt").dsFootnote()
                }

                Text("按钮").dsSectionTitle()
                VStack(spacing: 10) {
                    Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
                    Button("封盘") {}.buttonStyle(BluePillButtonStyle(fullWidth: true))
                    Button("接受 TA 的邀请") {}.buttonStyle(GhostPillButtonStyle())
                    Button("编辑") {}.buttonStyle(DarkUtilityButtonStyle())
                }

                Text("chip 分段").dsSectionTitle()
                HStack {
                    SelectableChip(title: "时间线", isSelected: true)
                    SelectableChip(title: "路线", isSelected: false)
                    SelectableChip(title: "计划", isSelected: false)
                }

                Text("卡片").dsSectionTitle()
                DarkCard {
                    VStack(spacing: 4) {
                        Text("距下次见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                        Text("12 天").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                        Text("查看行前计划 · 已安排 5 项 ›").font(.system(size: 13)).foregroundStyle(DS.skyBlue)
                    }
                }
                ParchmentCard {
                    HStack {
                        Text("今日心情").dsCaption()
                        Spacer()
                        Text("她还没打卡").dsFootnote()
                    }
                }
                GroupedSection {
                    GroupedRow(title: "她记了「外滩夜景」", value: "补上你的评价 ›", valueColor: DS.actionBlue)
                    GroupedRow(title: "经期第 2 天", value: "多关心她 ›")
                    GroupedRow(title: "昨天忘了封盘？", value: "一键补封 ›", valueColor: DS.actionBlue, showsDivider: false)
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .safeAreaInset(edge: .bottom) {
            FrostedBottomBar {
                HStack {
                    Text("已安排 5 项 · 完成 2 项").dsCaption()
                    Spacer()
                    Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
                }
            }
        }
    }
}

#Preview {
    DSGallery()
}
