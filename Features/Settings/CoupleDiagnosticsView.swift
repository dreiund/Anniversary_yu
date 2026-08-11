import SwiftUI
import CoreData

/// P6 追加:重复空间诊断清理页——设置页警示行点开。列出每个 couple 的归属/成员/数据计数,
/// 允许手动删除「非当前使用且完全为空」的残留(历史配对折腾留下的无标记空间,
/// pruneEmptyLocalCouple 的标记判据不敢碰,交给人工确认)。
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
                        Text("检测到 \(couples.count) 个空间。带「当前使用」的是正在生效的那份;空的残留可以放心删除,有数据的不提供删除。")
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
            .alert("删除这个空的空间?", isPresented: Binding(get: { pendingDelete != nil },
                                                       set: { if !$0 { pendingDelete = nil } })) {
                Button("删除", role: .destructive) {
                    if let couple = pendingDelete {
                        context.delete(couple)
                        try? context.save()
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("它名下没有任何数据,删除只是清掉这条残留记录,不影响正在使用的空间。")
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
                if !isActive && empty {
                    Button("删除这个空间") { pendingDelete = couple }
                        .font(.system(size: 14))
                        .foregroundStyle(DS.dsRed)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
}
