import SwiftUI

extension View {
    /// 首页大字（在一起 N 天）：SF 紧排
    func dsHero() -> some View {
        font(.system(size: 34, weight: .semibold)).tracking(-0.8).foregroundStyle(DS.ink)
    }

    /// 页面大标题（第 1 天 / 上海 · 8.29–9.02）
    func dsPageTitle() -> some View {
        font(.system(size: 22, weight: .semibold)).tracking(-0.4).foregroundStyle(DS.ink)
    }

    /// 区块标题（提醒 / 备忘 / 8月29日 周五）
    func dsSectionTitle() -> some View {
        font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
    }

    /// 正文 17pt（Apple 的阅读节奏）
    func dsBody() -> some View {
        font(.system(size: 17)).foregroundStyle(DS.ink)
    }

    func dsCaption() -> some View {
        font(.system(size: 14)).foregroundStyle(DS.inkMuted)
    }

    func dsFootnote() -> some View {
        font(.system(size: 12)).foregroundStyle(DS.inkMuted)
    }
}
