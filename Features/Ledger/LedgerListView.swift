import SwiftUI
import CoreData

/// 小本本三段（spec §四）：积极 / 消极 / 喜怒（喜怒段内 ❤/⚡ 分组）
enum LedgerSegment: CaseIterable {
    case praise, complaint, moods

    var label: String {
        switch self {
        case .praise: return "积极"
        case .complaint: return "消极"
        case .moods: return "喜怒"
        }
    }
}

/// 小本本列表（spec §四，小样选 A 双行 chips）
struct LedgerListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDLedgerEntry.createdAt, order: .reverse)])
    private var entries: FetchedResults<CDLedgerEntry>

    @State private var segment: LedgerSegment = .praise
    @State private var filter: LedgerFilter = .all

    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }

    /// 当前段 + 筛选的可见条目（isVisible 内嵌于 matches，私密过滤不旁路）
    private func filtered(categories: [LedgerCategory]) -> [CDLedgerEntry] {
        entries.filter { entry in
            categories.contains(LedgerCategory(rawValue: entry.categoryRaw) ?? .praise)
            && LedgerRules.matches(filter: filter, authorID: entry.authorPartnerID, myID: myID,
                                   visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt)
        }
    }

    var body: some View {
        let _ = entries.count   // FetchRequest 依赖注册：对方新记/公开实时上屏
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if segment == .moods {
                    moodsSection
                } else {
                    entriesSection(category: segment == .praise ? .praise : .complaint)
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("小本本")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(LedgerSegment.allCases, id: \.label) { seg in
                    SelectableChip(title: seg.label, isSelected: segment == seg) { segment = seg }
                }
            }
            HStack(spacing: 5) {
                ForEach(LedgerFilter.allCases, id: \.label) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.label)
                            .font(.system(size: 11, weight: filter == f ? .semibold : .regular))
                            .foregroundStyle(filter == f ? .white : DS.ink)
                            .padding(.vertical, 4).padding(.horizontal, 10)
                            .background(Capsule().fill(filter == f ? DS.actionBlue : DS.canvas))
                            .overlay(Capsule().stroke(filter == f ? DS.actionBlue : DS.chipBorder, lineWidth: 1))
                    }
                    .buttonStyle(DSPressEffect())
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(DS.canvas)
    }

    @ViewBuilder
    private func entriesSection(category: LedgerCategory) -> some View {
        let list = filtered(categories: [category])
        if list.isEmpty {
            emptyHint
        } else {
            ForEach(list, id: \.objectID) { entry in
                NavigationLink { Text(entry.title ?? "") } label: { entryCard(entry) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var moodsSection: some View {
        let likes = filtered(categories: [.like])
        let triggers = filtered(categories: [.trigger])
        if likes.isEmpty && triggers.isEmpty {
            emptyHint
        } else {
            if !likes.isEmpty {
                Text("❤ 喜欢").font(.system(size: 14, weight: .bold))
                ForEach(likes, id: \.objectID) { entry in
                    NavigationLink { Text(entry.title ?? "") } label: { moodCard(entry, accent: DS.dsGreen) }
                        .buttonStyle(.plain)
                }
            }
            if !triggers.isEmpty {
                Text("⚡ 雷区").font(.system(size: 14, weight: .bold)).padding(.top, 4)
                ForEach(triggers, id: \.objectID) { entry in
                    NavigationLink { Text(entry.title ?? "") } label: { moodCard(entry, accent: DS.dsOrange) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyHint: some View {
        Text("这一栏还是空的").dsCaption()
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
    }

    /// 积极/消极卡：徽章 + 标题 + 摘要 + meta + 首证据缩略
    private func entryCard(_ entry: CDLedgerEntry) -> some View {
        let accent = entry.categoryRaw == LedgerCategory.praise.rawValue ? DS.dsGreen : DS.dsOrange
        let thumb = LedgerRepository(context: context).evidencesSorted(entry).first?.thumbnailData
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text((LedgerCategory(rawValue: entry.categoryRaw) ?? .praise).title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.vertical, 1).padding(.horizontal, 7)
                    .overlay(Capsule().stroke(accent, lineWidth: 1))
                Text(entry.title ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer()
                if !LedgerRules.isRevealed(visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt) {
                    Text("🔒").font(.system(size: 10))
                }
            }
            if let detail = entry.detail, !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(DS.inkMuted).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(metaLine(entry)).dsFootnote()
                Spacer()
                if let thumb, let ui = UIImage(data: thumb) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
        .contentShape(Rectangle())
    }

    /// 喜怒卡：左描边 + 一句话 + meta（spec §四）
    private func moodCard(_ entry: CDLedgerEntry, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer()
                if !LedgerRules.isRevealed(visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt) {
                    Text("🔒").font(.system(size: 10))
                }
            }
            if let detail = entry.detail, !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.inkMuted).lineLimit(1)
            }
            Text(metaLine(entry)).dsFootnote()
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: DS.Radius.card, bottomLeadingRadius: DS.Radius.card,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(accent)
                .frame(width: 3)
        }
        .contentShape(Rectangle())
    }

    private func metaLine(_ entry: CDLedgerEntry) -> String {
        var parts: [String] = []
        parts.append("\(authorName(entry.authorPartnerID)) 记")
        if let at = entry.happenedAt { parts.append(Fmt.monthDay.string(from: at)) }
        if let placeName = entry.place?.name, !placeName.isEmpty { parts.append(placeName) }
        return parts.joined(separator: " · ")
    }

    private func authorName(_ id: UUID?) -> String {
        guard let id, let couple = couples.first else { return "" }
        let repo = CoupleRepository(context: context)
        if id == repo.currentPartnerID(of: couple) { return "我" }
        return repo.otherPartner(of: couple)?.name ?? "TA"
    }
}
