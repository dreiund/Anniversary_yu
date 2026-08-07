import SwiftUI
import CoreData

/// 小本本详情（spec §五，小样选 A 底部仪式钮）
struct LedgerDetailView: View {
    @ObservedObject var entry: CDLedgerEntry
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>

    @State private var confirmReveal = false
    @State private var confirmDelete = false
    @State private var showEdit = false
    @State private var viewerIndex: Int?

    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }
    private var isMine: Bool { LedgerRules.canEdit(authorID: entry.authorPartnerID, myID: myID) }
    private var revealed: Bool {
        LedgerRules.isRevealed(visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt)
    }
    private var category: LedgerCategory { LedgerCategory(rawValue: entry.categoryRaw) ?? .praise }
    private var accent: Color {
        switch category {
        case .praise, .like: return DS.dsGreen
        case .complaint, .trigger: return DS.dsOrange
        }
    }

    var body: some View {
        if entry.managedObjectContext == nil || entry.isDeleted {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        let evidences = LedgerRepository(context: context).evidencesSorted(entry)
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // 主体卡：实底类别徽章 + 标题 + 正文
                ParchmentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.vertical, 4).padding(.horizontal, 10)
                                .background(Capsule().fill(accent.opacity(0.14)))
                            Spacer()
                            if !revealed {
                                Text("🔒 仅自己可见").dsFootnote()
                            }
                        }
                        Text(entry.title ?? "").dsPageTitle()
                        if let detail = entry.detail, !detail.isEmpty {
                            Text(detail).dsBody().lineSpacing(5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 信息行：记录人 / 事发 / 地点 / 可见性
                GroupedSection {
                    ForEach(Array(infoRows.enumerated()), id: \.offset) { i, row in
                        GroupedRow(title: row.title, value: row.value,
                                   valueColor: row.color,
                                   showsDivider: i < infoRows.count - 1)
                    }
                }

                if !evidences.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("证据").dsSectionTitle()
                            Text("\(evidences.count) 张 · 点开大图").dsFootnote()
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(evidences.enumerated()), id: \.element.objectID) { i, evidence in
                                    if let data = evidence.thumbnailData, let ui = UIImage(data: data) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 110, height: 110)
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                            .dsPhotoShadow()
                                            .onTapGesture { viewerIndex = i }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 8)   // 给照片投影留出呼吸空间
                        }
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("编辑") { showEdit = true }
                        Button("删除", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isMine && !revealed {
                VStack(spacing: 6) {
                    Button("公开给 TA") { confirmReveal = true }
                        .buttonStyle(BluePillButtonStyle(fullWidth: true))
                    Text("公开后 TA 会收到轻通知，且不可撤回").dsFootnote()
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .alert("公开给 TA？", isPresented: $confirmReveal) {
            Button("公开") { try? LedgerRepository(context: context).reveal(entry, at: Date()) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("公开后 TA 会收到轻通知，且不可撤回。")
        }
        .alert("删除这条记录？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                try? LedgerRepository(context: context).delete(entry)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showEdit) {
            if category == .praise || category == .complaint {
                LedgerFormView(mode: .edit(entry))
            } else {
                QuickLedgerSheet(mode: .edit(entry))
            }
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { EvidenceIndex(id: $0) } },
            set: { viewerIndex = $0?.id })) { index in
            EvidenceViewer(evidences: evidences, index: index.id)
        }
    }

    private var infoRows: [(title: String, value: String, color: Color)] {
        var rows: [(String, String, Color)] = [("记录人", authorName.isEmpty ? "—" : authorName, DS.inkMuted)]
        if let at = entry.happenedAt {
            rows.append(("事发", Fmt.monthDay.string(from: at), DS.inkMuted))
        }
        if let placeName = entry.place?.name, !placeName.isEmpty {
            rows.append(("地点", placeName, DS.inkMuted))
        }
        if entry.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
            if let revealedAt = entry.revealedAt {
                rows.append(("可见性", "\(Fmt.monthDay.string(from: revealedAt)) 已公开", DS.dsGreen))
            } else {
                rows.append(("可见性", "仅自己可见 🔒", DS.inkMuted))
            }
        } else {
            rows.append(("可见性", "双方可见", DS.dsGreen))
        }
        return rows
    }

    private var authorName: String {
        guard let id = entry.authorPartnerID, let couple = couples.first else { return "" }
        let repo = CoupleRepository(context: context)
        if id == repo.currentPartnerID(of: couple) { return "我" }
        return repo.otherPartner(of: couple)?.name ?? "TA"
    }
}

private struct EvidenceIndex: Identifiable {
    let id: Int
}

/// 证据全屏浏览（轻量版 PhotoViewerView，CDEvidence 专用）
private struct EvidenceViewer: View {
    @Environment(\.dismiss) private var dismiss
    let evidences: [CDEvidence]
    @State var index: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(evidences.enumerated()), id: \.element.objectID) { i, evidence in
                    Group {
                        if let data = evidence.imageData, let ui = UIImage(data: data) {
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
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            .padding(.top, 8).padding(.leading, 14)
        }
    }
}
