import SwiftUI
import CoreData

/// 小本本四段（反馈⑨换壳）：好事(praise) / 生气(angry，内分「记一笔」complaint + 「⚡雷区」trigger 两组) / 喜好(likes) / 待办(todos)
enum LedgerSegment: CaseIterable {
    case praise, angry, likes, todos

    var label: String {
        switch self {
        case .praise: return "好事"
        case .angry: return "生气"
        case .likes: return "喜好"
        case .todos: return "待办"
        }
    }
}

/// 小本本列表（反馈⑨换壳：用户设计图布局，米色系——大标题+管理钮自绘头部、下划线二级筛选对四段都生效、统一白卡）
struct LedgerListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
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
    @State private var pushedTodo: CDTodoItem?
    @State private var pendingDeleteTodo: CDTodoItem?

    /// 默认落「好事」段；今天卡等入口可传段直达（如「待办」，反馈⑥ §四机制不变）
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
                case .angry: angrySection
                case .likes: entriesSection(category: .like)
                case .todos: todosSection
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.parchment)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { header }
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
        .alert("删除这条待办？", isPresented: Binding(get: { pendingDeleteTodo != nil },
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
        .navigationDestination(item: $pushedTodo) { TodoDetailView(todo: $0) }
    }

    /// 大标题 + 管理钮自绘头部（原 toolbar 管理钮已删，navigationTitle 置空避免与此重复）；
    /// 段 chips 下再是下划线二级筛选，四段都显示（反馈⑨换壳）
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("小本本").dsPageTitle()
                Spacer()
                Button(selecting ? "完成" : "管理") {
                    selecting.toggle(); selected = []; openSwipeID = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ink)
                .padding(.vertical, 6).padding(.horizontal, 14)
                .background(Capsule().fill(DS.canvas))
                .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))
            }
            HStack(spacing: 6) {
                ForEach(LedgerSegment.allCases, id: \.label) { seg in
                    Button { segment = seg } label: {
                        Text(seg.label)
                            .font(.system(size: 14, weight: segment == seg ? .semibold : .regular))
                            .foregroundStyle(segment == seg ? DS.ink : DS.inkMuted)
                            .padding(.vertical, 7).padding(.horizontal, 14)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(segment == seg ? DS.canvas : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(segment == seg ? DS.hairline : .clear, lineWidth: 1))
                    }
                    .buttonStyle(DSPressEffect())
                }
            }
            HStack(spacing: 16) {
                ForEach(LedgerFilter.allCases, id: \.label) { f in
                    Button { filter = f } label: {
                        VStack(spacing: 3) {
                            Text(f.label)
                                .font(.system(size: 12, weight: filter == f ? .semibold : .regular))
                                .foregroundStyle(filter == f ? DS.actionBlue : DS.inkMuted)
                            Rectangle().fill(filter == f ? DS.actionBlue : .clear)
                                .frame(height: 2).clipShape(Capsule())
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, DS.Spacing.md).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.parchment)
    }

    @ViewBuilder
    private func entriesSection(category: LedgerCategory) -> some View {
        let list = filtered(categories: [category])
        if list.isEmpty {
            emptyHint
        } else {
            // 调用方只传 .praise("好事")或 .like("喜好")两段(生气段走 angrySection、待办段走
            // todosSection，均不经此处)——三目 else 分支等价于 .like，不会误配其它分类的图标
            ForEach(list, id: \.objectID) { entry in
                entryRow(entry) { newCard(entry, icon: category == .praise ? "heart" : "star") }
            }
        }
    }

    /// 生气段：「记一笔」complaint + 「⚡ 雷区」trigger 两组小标题（反馈⑨换壳，原喜怒段拆分）
    @ViewBuilder
    private var angrySection: some View {
        let complaints = filtered(categories: [.complaint])
        let triggers = filtered(categories: [.trigger])
        if complaints.isEmpty && triggers.isEmpty {
            emptyHint
        } else {
            if !complaints.isEmpty {
                Text("记一笔").font(.system(size: 13, weight: .bold)).foregroundStyle(DS.inkMuted)
                ForEach(complaints, id: \.objectID) { entry in
                    entryRow(entry) { newCard(entry, icon: "cloud.drizzle") }
                }
            }
            if !triggers.isEmpty {
                Text("⚡ 雷区").font(.system(size: 13, weight: .bold)).foregroundStyle(DS.inkMuted).padding(.top, 4)
                ForEach(triggers, id: \.objectID) { entry in
                    entryRow(entry) { newCard(entry, icon: "bolt") }
                }
            }
        }
    }

    /// 待办段：不再分「我做/Ta做」两组，按 TodoRules.sortKey 合成一列平铺，行内徽标区分我做/Ta做；
    /// 二级筛选四档与小本本条目同口径生效（LedgerRules.matches，author 维度——不是 assignee 维度）
    @ViewBuilder
    private var todosSection: some View {
        let repo = TodoRepository(context: context)
        let all = couples.first.map { repo.todos(couple: $0) } ?? []
        let visible = all.filter {
            TodoRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        let matched = visible.filter {
            LedgerRules.matches(filter: filter, authorID: $0.authorPartnerID, myID: myID,
                                visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        let sorted = matched.sorted { TodoRules.sortKey(isDone: $0.isDone, dueAt: $0.dueAt, doneAt: $0.doneAt)
                                     < TodoRules.sortKey(isDone: $1.isDone, dueAt: $1.dueAt, doneAt: $1.doneAt) }
        if sorted.isEmpty {
            emptyHint
        } else {
            ForEach(sorted, id: \.objectID) { todoRowEntry($0) }
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

    /// 待办行外层包装：左滑删仅作者，点行统一推入详情（R17 §二:作者/非作者同路，不再分叉编辑表单/只读详情）；
    /// 行体本身换成 TodoRow（R17 §五根修：行级 @ObservedObject 订阅，见文件底部）
    @ViewBuilder
    private func todoRowEntry(_ todo: CDTodoItem) -> some View {
        let canEdit = TodoRules.canEdit(authorID: todo.authorPartnerID, myID: myID)
        let row = TodoRow(todo: todo, myID: myID) { pushedTodo = todo }
        if canEdit {
            SwipeDeleteRow(id: todo.objectID, openID: $openSwipeID) {
                pendingDeleteTodo = todo
            } content: { row }
        } else {
            row
        }
    }

    private var emptyHint: some View {
        Text("这一栏还是空的").dsCaption()
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
    }

    /// 反馈⑨新卡：白底+hairline 描边+圆角 14+左圆底图标+标题/详情/脚注（用户设计图版式，米色系）
    private func newCard(_ entry: CDLedgerEntry, icon: String) -> some View {
        let thumb = LedgerRepository(context: context).evidencesSorted(entry).first?.thumbnailData
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(DS.parchment).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(DS.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title ?? "").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.ink).lineLimit(1)
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
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

/// R17 §五根修：行级 @ObservedObject 订阅对象变更——父视图重算与否都能重绘
/// (R12 MemoRow 同款；此前 todoRow 是内联 builder，isDone 翻转不改 todoItems.count，行不刷新)
private struct TodoRow: View {
    @ObservedObject var todo: CDTodoItem
    let myID: UUID?
    var onTap: () -> Void
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                           assigneeID: todo.assigneePartnerID, myID: myID) {
                    try? TodoRepository(context: context).setDone(todo, done: !todo.isDone, at: Date())
                    if todo.isDone, let id = todo.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.todoID(id))   // 完成即取消提醒
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(DS.parchment).frame(width: 34, height: 34)
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(todo.isDone ? DS.actionBlue : DS.chipBorder)
                }
            }
            .buttonStyle(DSPressEffect())
            .accessibilityLabel("\(todo.isDone ? "取消完成" : "完成") \(todo.title ?? "")")
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? DS.inkMuted : DS.ink)
                    .strikethrough(todo.isDone, color: DS.inkMuted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(meta).dsFootnote()
                    Spacer()
                    if let thumb = TodoRepository(context: context).evidencesSorted(todo).first?.thumbnailData,
                       let ui = UIImage(data: thumb) {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var meta: String {
        var parts: [String] = []
        if let due = todo.dueAt { parts.append(Fmt.monthDay.string(from: due)) }
        if !LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt) {
            parts.append("🔒")
        }
        if todo.isDone { parts.append("已完成") }
        parts.append(todo.assigneePartnerID == myID ? "我做" : "Ta做")
        return parts.joined(separator: " · ")
    }
}
