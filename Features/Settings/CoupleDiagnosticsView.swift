import SwiftUI
import CoreData

/// P6 追加:重复空间诊断清理页——设置页警示行点开。列出每个 couple 的归属/成员/数据计数。
/// 删除即选择(用户定稿):非当前空间一律可删(有数据的强确认列明计数),删到只剩一个
/// 它就是使用中的空间;「当前使用」永不可删——误删=两人数据全没且同步回 iCloud。
struct CoupleDiagnosticsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)])
    private var couples: FetchedResults<CDCouple>
    @State private var pendingDelete: CDCouple?

    var body: some View {
        let repo = CoupleRepository(context: context)
        let active = try? repo.fetchCouple()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if couples.count <= 1 {
                        Text("只有一个空间,一切正常 · 残留已清理")
                            .dsCaption()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        Text("检测到 \(couples.count) 个空间。带「当前使用」的是正在生效的那份、不可删除;其余空间都可删——删到只剩一个,它就是你们使用的空间。")
                            .dsFootnote()
                    }
                    ForEach(couples, id: \.objectID) { couple in
                        coupleCard(couple, repo: repo, isActive: couple.objectID == active?.objectID)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle("空间诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .alert("删除这个空间?", isPresented: Binding(get: { pendingDelete != nil },
                                                    set: { if !$0 { pendingDelete = nil } })) {
                Button("删除", role: .destructive) {
                    if let couple = pendingDelete { deleteCouple(couple, repo: repo) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text(deleteMessage(pendingDelete, repo: repo))
            }
        }
    }

    @ViewBuilder
    private func coupleCard(_ couple: CDCouple, repo: CoupleRepository, isActive: Bool) -> some View {
        let partners = repo.partners(of: couple)
        let empty = !repo.hasAnyData(couple)
        let meetings = (couple.meetings as? Set<CDMeeting>)?.count ?? 0
        let places = (couple.places as? Set<CDPlace>)?.count ?? 0
        let entries = (couple.ledgerEntries as? Set<CDLedgerEntry>)?.count ?? 0
        let todos = (couple.todos as? Set<CDTodoItem>)?.count ?? 0
        let cycles = (couple.cycles as? Set<CDCycle>)?.count ?? 0

        GroupedSection {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(repo.isParticipantDevice(couple) ? "共享空间" : "本机空间")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                    if isActive {
                        Text("当前使用")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.vertical, 2).padding(.horizontal, 7)
                            .background(Capsule().fill(DS.dsGreen))
                    }
                    Spacer()
                    if let created = couple.createdAt {
                        Text(Fmt.monthDay.string(from: created)).dsFootnote()
                    }
                }
                Text("成员:\(partners.compactMap(\.name).joined(separator: "、").isEmpty ? "—" : partners.compactMap(\.name).joined(separator: "、"))")
                    .dsFootnote()
                Text(empty ? "没有任何数据" : "见面 \(meetings) · 地点 \(places) · 小本本 \(entries) · 待办 \(todos) · 周期 \(cycles)")
                    .dsFootnote()
                // 删除即选择(用户定稿):非当前空间一律可删;当前使用的永不可删(误删=两人数据全没)
                if !isActive {
                    Button(empty ? "删除这个空间" : "删除这个空间(含数据)") { pendingDelete = couple }
                        .font(.system(size: 14))
                        .foregroundStyle(DS.dsRed)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private func deleteMessage(_ couple: CDCouple?, repo: CoupleRepository) -> String {
        guard let couple else { return "" }
        if !repo.hasAnyData(couple) {
            return "它名下没有任何数据,删除只是清掉这条残留记录,不影响正在使用的空间。"
        }
        let meetings = (couple.meetings as? Set<CDMeeting>)?.count ?? 0
        let places = (couple.places as? Set<CDPlace>)?.count ?? 0
        let entries = (couple.ledgerEntries as? Set<CDLedgerEntry>)?.count ?? 0
        let todos = (couple.todos as? Set<CDTodoItem>)?.count ?? 0
        let cycles = (couple.cycles as? Set<CDCycle>)?.count ?? 0
        return "它名下的数据会一并删除(见面 \(meetings) · 地点 \(places) · 小本本 \(entries) · 待办 \(todos) · 周期 \(cycles)),并同步到 iCloud,无法恢复。"
    }

    /// 级联删除整个空间;删除前取消名下待办与日程的本机提醒(不留野闹钟)
    private func deleteCouple(_ couple: CDCouple, repo: CoupleRepository) {
        let todoIDs = ((couple.todos as? Set<CDTodoItem>) ?? []).compactMap(\.id)
        for id in todoIDs { ReminderScheduler.cancel(id: ReminderPlanner.todoID(id)) }
        let planIDs = ((couple.meetings as? Set<CDMeeting>) ?? [])
            .flatMap { ($0.planItems as? Set<CDPlanItem>) ?? [] }
            .compactMap(\.id)
        ReminderScheduler.cancelPlans(planIDs)
        context.delete(couple)
        try? context.save()
    }
}
