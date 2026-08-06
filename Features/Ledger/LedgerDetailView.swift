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
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: 6) {
                    Text(category.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.vertical, 2).padding(.horizontal, 8)
                        .overlay(Capsule().stroke(accent, lineWidth: 1))
                    if !revealed {
                        Text("🔒 仅自己可见").dsFootnote()
                    }
                }
                Text(entry.title ?? "").dsPageTitle()
                Text(metaLine).dsFootnote()
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail).dsBody().padding(.top, 4)
                }
                if !evidences.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(evidences.enumerated()), id: \.element.objectID) { i, evidence in
                            if let data = evidence.thumbnailData, let ui = UIImage(data: data) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 74, height: 74)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                    .onTapGesture { viewerIndex = i }
                            }
                        }
                    }
                    .padding(.top, 6)
                    Text("证据 \(evidences.count) 张 · 点开大图").dsFootnote()
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

    private var metaLine: String {
        var parts = ["\(authorName) 记"]
        if let at = entry.happenedAt { parts.append("事发 \(Fmt.monthDay.string(from: at))") }
        if let placeName = entry.place?.name, !placeName.isEmpty { parts.append(placeName) }
        if entry.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue,
           let revealedAt = entry.revealedAt {
            parts.append("\(Fmt.monthDay.string(from: revealedAt)) 已公开")
        }
        return parts.joined(separator: " · ")
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
