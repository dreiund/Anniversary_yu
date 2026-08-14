import SwiftUI
import CoreData

/// 待办详情(R17 §二,1A 推入式):版式照 LedgerDetailView——主体卡+信息行+地点行+照片区,
/// 作者右上「⋯」编辑/删除,canToggle 者底部完成大钮;公开仍走表单开关,本页不设公开钮(spec §八)
struct TodoDetailView: View {
    @ObservedObject var todo: CDTodoItem
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>

    @State private var confirmDelete = false
    @State private var showEdit = false
    @State private var showMiniMap = false
    @State private var viewerIndex: Int?

    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }
    private var isMine: Bool { TodoRules.canEdit(authorID: todo.authorPartnerID, myID: myID) }
    private var canToggle: Bool {
        TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                assigneeID: todo.assigneePartnerID, myID: myID)
    }
    private var revealed: Bool {
        LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt)
    }

    var body: some View {
        if todo.managedObjectContext == nil || todo.isDeleted {
            Color.clear.onAppear { dismiss() }   // 对方远程删除守卫(P6 F-2 同款)
        } else {
            content
        }
    }

    private var content: some View {
        let evidences = TodoRepository(context: context).evidencesSorted(todo)
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ParchmentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("待办 · \(todo.assigneePartnerID == myID ? "我做" : "Ta做")")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.actionBlue)
                                .padding(.vertical, 4).padding(.horizontal, 10)
                                .background(Capsule().fill(DS.actionBlue.opacity(0.14)))
                            Spacer()
                            if !revealed {
                                Text("🔒 仅自己可见").dsFootnote()
                            }
                        }
                        Text(todo.title ?? "").dsPageTitle()
                        if let detail = todo.detail, !detail.isEmpty {
                            Text(detail).dsBody().lineSpacing(5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupedSection {
                    ForEach(Array(infoRows.enumerated()), id: \.offset) { i, row in
                        GroupedRow(title: row.title, value: row.value,
                                   valueColor: row.color,
                                   showsDivider: i < infoRows.count - 1)
                    }
                }

                if let place = todo.place {
                    GroupedSection {
                        HStack {
                            Button {
                                if place.latitude != 0 || place.longitude != 0 { showMiniMap = true }
                            } label: {
                                Text("📍 \(place.name ?? "")").dsBody()
                                    .foregroundStyle(place.latitude != 0 || place.longitude != 0
                                                     ? DS.actionBlue : DS.inkMuted)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if place.latitude != 0 || place.longitude != 0 {
                                Button("导航") { openInMapsNavigation(place: place) }
                                    .buttonStyle(SmallBluePillButtonStyle())
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }

                if !evidences.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("照片").dsSectionTitle()
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
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("待办")
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
                    .accessibilityLabel("待办详情菜单")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canToggle {
                Button(todo.isDone ? "取消完成" : "完成") {
                    try? TodoRepository(context: context).setDone(todo, done: !todo.isDone, at: Date())
                    if todo.isDone, let id = todo.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.todoID(id))   // 完成即取消提醒
                    }
                }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .alert("删除这条待办？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                let id = todo.id
                try? TodoRepository(context: context).delete(todo)
                if let id { ReminderScheduler.cancel(id: ReminderPlanner.todoID(id)) }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showEdit) { TodoFormView(mode: .edit(todo)) }
        .sheet(isPresented: $showMiniMap) {
            if let place = todo.place { PlaceMiniMapSheet(place: place) }
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { EvidenceIndex(id: $0) } },
            set: { viewerIndex = $0?.id })) { index in
            EvidenceViewer(evidences: evidences, index: index.id)
        }
    }

    private var infoRows: [(title: String, value: String, color: Color)] {
        var rows: [(String, String, Color)] = [("记录人", authorName.isEmpty ? "—" : authorName, DS.inkMuted)]
        rows.append(("目标日", todo.dueAt.map { Fmt.monthDay.string(from: $0) } ?? "—", DS.inkMuted))
        if let remindAt = todo.remindAt {
            rows.append(("提醒", Fmt.monthDayHM.string(from: remindAt), DS.inkMuted))
        }
        if todo.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
            if let revealedAt = todo.revealedAt {
                rows.append(("可见性", "\(Fmt.monthDay.string(from: revealedAt)) 已公开", DS.dsGreen))
            } else {
                rows.append(("可见性", "仅自己可见 🔒", DS.inkMuted))
            }
        } else {
            rows.append(("可见性", "双方可见", DS.dsGreen))
        }
        rows.append(("完成态", todo.isDone ? "已完成" : "未完成", todo.isDone ? DS.dsGreen : DS.inkMuted))
        return rows
    }

    private var authorName: String {
        guard let id = todo.authorPartnerID, let couple = couples.first else { return "" }
        let repo = CoupleRepository(context: context)
        if id == repo.currentPartnerID(of: couple) { return "我" }
        return repo.otherPartner(of: couple)?.name ?? "TA"
    }
}
