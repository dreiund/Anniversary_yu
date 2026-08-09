import SwiftUI
import CoreData

/// 反馈⑨:行前日程只读查看页——点行先看,右上「编辑」才进表单;带坐标地点可直接导航
struct PlanItemDetailSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: CDPlanItem
    @State private var showEdit = false
    @State private var showMiniMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? "").dsPageTitle()
                        if let moment = PlanItemRepository(context: context).plannedMoment(of: item) {
                            HStack(spacing: 4) {
                                Text(item.time == nil
                                     ? Fmt.monthDayWeek.string(from: moment)
                                     : "\(Fmt.monthDayWeek.string(from: moment)) \(Fmt.hm.string(from: moment))")
                                    .dsCaption()
                                if item.remindAt != nil { Text("⏰").font(.system(size: 11)) }
                            }
                        }
                    }
                    if let place = item.place {
                        GroupedSection {
                            HStack {
                                Button {
                                    if place.latitude != 0 || place.longitude != 0 { showMiniMap = true }
                                } label: {
                                    Text("📍 \(place.name ?? "")").dsBody().foregroundStyle(DS.ink)
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
                    } else if let text = item.placeText, !text.isEmpty {
                        GroupedSection {
                            Text("📍 \(text)").dsBody()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                    if let note = item.note, !note.isEmpty {
                        GroupedSection {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("备注").dsFootnote()
                                Text(note).dsBody()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                    HStack(spacing: 6) {
                        AvatarInitial(name: authorName(item.authorPartnerID), size: 20)
                        Text("\(authorName(item.authorPartnerID)) 安排的").dsFootnote()
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle("日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("编辑") { showEdit = true } }
            }
            .sheet(isPresented: $showEdit, onDismiss: {
                // 表单里删除了此项 → 查看页失去对象,跟着退场
                if item.managedObjectContext == nil || item.isDeleted { dismiss() }
            }) {
                if let meeting = item.meeting { PlanItemFormSheet(meeting: meeting, item: item) }
            }
            .sheet(isPresented: $showMiniMap) {
                if let place = item.place { PlaceMiniMapSheet(place: place) }
            }
        }
    }

    /// spec §三「作者小签」——与 PlanView.authorName(_:) 同款实现
    private func authorName(_ id: UUID?) -> String {
        let repo = CoupleRepository(context: context)
        guard let id, let couple = try? repo.fetchCouple() else { return "" }
        return repo.partners(of: couple).first { $0.id == id }?.name ?? ""
    }
}

/// 小尺寸行动蓝药丸:DSButtons 里的 BluePillButtonStyle 是大号 CTA 尺寸(17pt/11·22 内边距),
/// 查看页地点行内联「导航」按钮需要紧凑尺寸,自绘一个小号版本。
private struct SmallBluePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Capsule().fill(DS.actionBlue))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 反馈⑨终审修:导航统一走 AmapNavigator(高德优先,未装退苹果地图;GCJ-02 国内坐标坑见该文件注释)——
/// 原先这里直跳苹果地图,与地点档案页「导航到这里」形成同屏两套导航标准,现收敛为一套(小地图/日程查看页共用)
@MainActor
func openInMapsNavigation(place: CDPlace) {
    AmapNavigator.navigate(name: place.name ?? "目的地", latitude: place.latitude, longitude: place.longitude)
}
