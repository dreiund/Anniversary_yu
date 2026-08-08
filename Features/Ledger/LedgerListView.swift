import SwiftUI
import CoreData

/// 小本本四段（spec §四 / 反馈⑥ §四）：积极 / 消极 / 喜怒（喜怒段内 ❤/⚡ 分组）/ 记得做
enum LedgerSegment: CaseIterable {
    case praise, complaint, moods, todos

    var label: String {
        switch self {
        case .praise: return "积极"
        case .complaint: return "消极"
        case .moods: return "喜怒"
        case .todos: return "记得做"
        }
    }
}

/// 小本本列表（spec §四，小样选 A 双行 chips）
struct LedgerListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDLedgerEntry.createdAt, order: .reverse)])
    private var entries: FetchedResults<CDLedgerEntry>
    @FetchRequest(sortDescriptors: []) private var todoItems: FetchedResults<CDTodoItem>

    @State private var segment: LedgerSegment
    @State private var filter: LedgerFilter = .all
    @State private var selecting = false
    @State private var selected: Set<NSManagedObjectID> = []
    @State private var confirmBatch = false
    @State private var openSwipeID: NSManagedObjectID?
    @State private var pendingDelete: CDLedgerEntry?
    @State private var editingTodo: CDTodoItem?
    @State private var viewingTodo: CDTodoItem?
    @State private var pendingDeleteTodo: CDTodoItem?

    /// 默认落「积极」段；今天卡等入口可传段直达（如「记得做」，反馈⑥ §四）
    init(initialSegment: LedgerSegment = .praise) {
        _segment = State(initialValue: initialSegment)
    }

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
        let _ = (entries.count, todoItems.count)   // FetchRequest 依赖注册：对方新记/公开实时上屏
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                switch segment {
                case .praise: entriesSection(category: .praise)
                case .complaint: entriesSection(category: .complaint)
                case .moods: moodsSection
                case .todos: todosSection
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("小本本")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar {
            if entries.contains(where: { LedgerRules.canEdit(authorID: $0.authorPartnerID, myID: myID) }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "管理") {
                        selecting.toggle()
                        selected = []
                        openSwipeID = nil
                    }
                    .font(.system(size: 14))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                FrostedBottomBar {
                    BatchDeleteBar(count: selected.count) { confirmBatch = true }
                }
            }
        }
        .alert("删除所选 \(selected.count) 项？", isPresented: $confirmBatch) {
            Button("删除所选", role: .destructive) {
                let picked = selected.compactMap {
                    try? context.existingObject(with: $0) as? CDLedgerEntry
                }
                try? LedgerRepository(context: context).delete(picked)
                selected = []
                selecting = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选记录会删除，无法恢复。")
        }
        .alert("删除这条记录？", isPresented: Binding(get: { pendingDelete != nil },
                                              set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let entry = pendingDelete {
                    try? LedgerRepository(context: context).delete(entry)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .alert("删除这条记得做？", isPresented: Binding(get: { pendingDeleteTodo != nil },
                                              set: { if !$0 { pendingDeleteTodo = nil } })) {
            Button("删除", role: .destructive) {
                if let todo = pendingDeleteTodo {
                    let id = todo.id
                    try? TodoRepository(context: context).delete(todo)
                    if let id { ReminderScheduler.cancel(id: ReminderPlanner.todoID(id)) }
                }
                pendingDeleteTodo = nil
            }
            Button("取消", role: .cancel) { pendingDeleteTodo = nil }
        }
        .sheet(item: $editingTodo) { TodoFormView(mode: .edit($0)) }
        .sheet(item: $viewingTodo) { TodoDetailSheet(todo: $0, myID: myID) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(LedgerSegment.allCases, id: \.label) { seg in
                    SelectableChip(title: seg.label, isSelected: segment == seg) { segment = seg }
                }
            }
            if segment != .todos {
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
                entryRow(entry) { entryCard(entry) }
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
                    entryRow(entry) { moodCard(entry, accent: DS.dsGreen) }
                }
            }
            if !triggers.isEmpty {
                Text("⚡ 雷区").font(.system(size: 14, weight: .bold)).padding(.top, 4)
                ForEach(triggers, id: \.objectID) { entry in
                    entryRow(entry) { moodCard(entry, accent: DS.dsOrange) }
                }
            }
        }
    }

    /// 记得做段：我做/Ta做两组，各自未完成按目标日升序、已完成沉底（TodoRules.sortKey）
    @ViewBuilder
    private var todosSection: some View {
        let repo = TodoRepository(context: context)
        let all = couples.first.map { repo.todos(couple: $0) } ?? []
        let visible = all.filter {
            TodoRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        let mine = visible.filter { $0.assigneePartnerID == myID }
            .sorted { TodoRules.sortKey(isDone: $0.isDone, dueAt: $0.dueAt, doneAt: $0.doneAt)
                    < TodoRules.sortKey(isDone: $1.isDone, dueAt: $1.dueAt, doneAt: $1.doneAt) }
        let theirs = visible.filter { $0.assigneePartnerID != myID }
            .sorted { TodoRules.sortKey(isDone: $0.isDone, dueAt: $0.dueAt, doneAt: $0.doneAt)
                    < TodoRules.sortKey(isDone: $1.isDone, dueAt: $1.dueAt, doneAt: $1.doneAt) }
        if mine.isEmpty && theirs.isEmpty {
            emptyHint
        } else {
            if !mine.isEmpty {
                Text("📌 我做").font(.system(size: 14, weight: .bold))
                ForEach(mine, id: \.objectID) { todoRow($0) }
            }
            if !theirs.isEmpty {
                Text("👉 Ta做").font(.system(size: 14, weight: .bold)).padding(.top, 4)
                ForEach(theirs, id: \.objectID) { todoRow($0) }
            }
        }
    }

    /// 行包装：删除只有作者能做（LedgerRules.canEdit）——我的条目给左滑与勾选，
    /// 对方的照常进详情；管理模式下对方条目淡显示意不可选
    @ViewBuilder
    private func entryRow<Card: View>(_ entry: CDLedgerEntry,
                                      @ViewBuilder card: @escaping () -> Card) -> some View {
        let mine = LedgerRules.canEdit(authorID: entry.authorPartnerID, myID: myID)
        if selecting {
            if mine {
                Button {
                    if selected.contains(entry.objectID) { selected.remove(entry.objectID) }
                    else { selected.insert(entry.objectID) }
                } label: {
                    HStack(spacing: 10) {
                        SelectionCircle(isOn: selected.contains(entry.objectID), size: 20)
                        card()
                    }
                }
                .buttonStyle(DSPressEffect())
            } else {
                card().opacity(0.45)
            }
        } else if mine {
            SwipeDeleteRow(id: entry.objectID, openID: $openSwipeID) {
                pendingDelete = entry
            } content: {
                NavigationLink { LedgerDetailView(entry: entry) } label: { card() }
                    .buttonStyle(.plain)
            }
        } else {
            NavigationLink { LedgerDetailView(entry: entry) } label: { card() }
                .buttonStyle(.plain)
        }
    }

    /// 记得做行：勾选圈（作者或 assignee 可点）+ 内容，左滑删仅作者，点行→作者编辑/非作者只读详情
    @ViewBuilder
    private func todoRow(_ todo: CDTodoItem) -> some View {
        let canEdit = TodoRules.canEdit(authorID: todo.authorPartnerID, myID: myID)
        let row = HStack(spacing: 10) {
            Button {
                if TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                           assigneeID: todo.assigneePartnerID, myID: myID) {
                    try? TodoRepository(context: context).setDone(todo, done: !todo.isDone, at: Date())
                    if todo.isDone, let id = todo.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.todoID(id))   // 完成即取消提醒
                    }
                }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(todo.isDone ? DS.actionBlue : DS.chipBorder)
            }
            .buttonStyle(DSPressEffect())
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? DS.inkMuted : DS.ink)
                    .strikethrough(todo.isDone, color: DS.inkMuted)
                Text(todoMeta(todo)).dsFootnote()
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
        .contentShape(Rectangle())
        .onTapGesture {
            if canEdit { editingTodo = todo } else { viewingTodo = todo }
        }
        if canEdit {
            SwipeDeleteRow(id: todo.objectID, openID: $openSwipeID) {
                pendingDeleteTodo = todo
            } content: {
                row
            }
        } else {
            row
        }
    }

    private func todoMeta(_ todo: CDTodoItem) -> String {
        var parts: [String] = []
        if let due = todo.dueAt { parts.append(Fmt.monthDay.string(from: due)) }
        if !LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt) {
            parts.append("🔒")
        }
        if todo.isDone { parts.append("已完成") }
        return parts.joined(separator: " · ")
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

/// 记得做只读详情（非作者点行，反馈⑥ §四）：GroupedSection 行式全览
/// + assignee 可用的完成/取消完成大钮（勾选走 repo.setDone，完成时取消提醒）
private struct TodoDetailSheet: View {
    @ObservedObject var todo: CDTodoItem
    let myID: UUID?
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var canToggle: Bool {
        TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                assigneeID: todo.assigneePartnerID, myID: myID)
    }

    private var rows: [(title: String, value: String, color: Color)] {
        var result: [(String, String, Color)] = [("标题", todo.title ?? "—", DS.ink)]
        if let detail = todo.detail, !detail.isEmpty {
            result.append(("详情", detail, DS.inkMuted))
        } else {
            result.append(("详情", "—", DS.inkMuted))
        }
        if let due = todo.dueAt {
            result.append(("目标日", Fmt.monthDay.string(from: due), DS.inkMuted))
        } else {
            result.append(("目标日", "—", DS.inkMuted))
        }
        if let placeName = todo.place?.name, !placeName.isEmpty {
            result.append(("地点", placeName, DS.inkMuted))
        } else {
            result.append(("地点", "—", DS.inkMuted))
        }
        if todo.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
            if let revealedAt = todo.revealedAt {
                result.append(("可见性", "\(Fmt.monthDay.string(from: revealedAt)) 已公开", DS.dsGreen))
            } else {
                result.append(("可见性", "仅自己可见 🔒", DS.inkMuted))
            }
        } else {
            result.append(("可见性", "双方可见", DS.dsGreen))
        }
        result.append(("完成态", todo.isDone ? "已完成" : "未完成", todo.isDone ? DS.dsGreen : DS.inkMuted))
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GroupedSection {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GroupedRow(title: row.title, value: row.value, valueColor: row.color,
                                   showsDivider: i < rows.count - 1)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.canvas)
            .navigationTitle("记得做")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
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
        }
    }
}
