import SwiftUI
import CoreData

/// 反馈⑨:行前日程只读查看页——点行先看,右上「编辑」才进表单;带坐标地点可直接导航
struct PlanItemDetailSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    // R18 热修:@ObservedObject 订阅对象变更——表单里公开/改动后查看页即时刷新(原 let 持有不感知)
    @ObservedObject var item: CDPlanItem
    @State private var showEdit = false
    @State private var showMiniMap = false
    @State private var viewerIndex: Int?

    var body: some View {
        // 对象删除守卫(P6 F-2 同款):表单里删除后本页对象失效,立即退场
        if item.managedObjectContext == nil || item.isDeleted {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
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
                    if item.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
                        GroupedSection {
                            HStack {
                                Text("可见性").dsBody()
                                Spacer()
                                Text(item.revealedAt.map { "\(Fmt.monthDay.string(from: $0)) 已公开" }
                                     ?? "仅自己可见 🔒")
                                    .dsCaption()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                    let evidences = PlanItemRepository(context: context).evidencesSorted(item)
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
                                .padding(.horizontal, 2).padding(.vertical, 8)
                            }
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
            .fullScreenCover(item: Binding(
                get: { viewerIndex.map { EvidenceIndex(id: $0) } },
                set: { viewerIndex = $0?.id })) { index in
                EvidenceViewer(evidences: PlanItemRepository(context: context).evidencesSorted(item),
                               index: index.id)
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

/// 反馈⑨终审修:导航统一走 AmapNavigator(高德优先,未装退苹果地图;GCJ-02 国内坐标坑见该文件注释)——
/// 原先这里直跳苹果地图,与地点档案页「导航到这里」形成同屏两套导航标准,现收敛为一套(小地图/日程查看页共用)
@MainActor
func openInMapsNavigation(place: CDPlace) {
    AmapNavigator.navigate(name: place.name ?? "目的地", latitude: place.latitude, longitude: place.longitude)
}
