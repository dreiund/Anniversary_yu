import SwiftUI

struct MomentDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// 观察 moment 自身属性与关系变化（移动到其他日、照片增删、换地点会触发）。
    /// 评价对象自身属性的更新不走此通道——依赖本页各 sheet 收起时的 @State 变化重算 body；跨设备远程更新的实时刷新延后 P6。
    @ObservedObject var moment: CDMoment
    @State private var viewerIndex: ViewerIndex?
    @State private var showEdit = false
    @State private var showEvalForm = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false

    var body: some View {
        let repo = MomentRepository(context: context)
        let photos = repo.photosSorted(moment)
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let me = couple.flatMap { couples.currentPartner(of: $0) }
        let other = couple.flatMap { couples.otherPartner(of: $0) }
        let myEval = me.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let otherEval = other.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = other?.name ?? "TA"

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if !photos.isEmpty {
                    TabView {
                        ForEach(Array(photos.enumerated()), id: \.element.objectID) { i, photo in
                            if let thumb = photo.thumbnailData ?? photo.imageData,
                               let ui = UIImage(data: thumb) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .onTapGesture { viewerIndex = ViewerIndex(id: i) }
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                    .dsPhotoShadow()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\((MomentType(rawValue: moment.typeRaw) ?? .other).title) · 第 \(moment.dateDay?.dayIndex ?? 0) 天 · \(moment.happenedAt.map { Fmt.hm.string(from: $0) } ?? "")")
                        .dsFootnote()
                    Text(moment.title ?? "").dsPageTitle()
                    if let place = moment.place?.name {
                        Text(place).font(.system(size: 13)).foregroundStyle(DS.actionBlue)
                    }
                }

                ParchmentCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if let myEval {
                            HStack(spacing: 6) {
                                Text("你").dsCaption()
                                StarsView(stars: Int(myEval.stars))
                                if let emoji = myEval.moodEmoji { Text(emoji) }
                            }
                            if let comment = myEval.comment {
                                Text("\u{201c}\(comment)\u{201d}").dsBody()
                            }
                            Button("改我的评价") { showEvalForm = true }
                                .font(.system(size: 13))
                                .foregroundStyle(DS.actionBlue)
                                .buttonStyle(.plain)
                        } else {
                            Button("补上评价") { showEvalForm = true }
                                .buttonStyle(GhostPillButtonStyle())
                        }
                        DS.hairline.frame(height: 1)
                        if let otherEval {
                            HStack(spacing: 6) {
                                Text(partnerName).dsCaption()
                                StarsView(stars: Int(otherEval.stars))
                                if let emoji = otherEval.moodEmoji { Text(emoji) }
                            }
                            if let comment = otherEval.comment, !comment.isEmpty {
                                Text("\u{201c}\(comment)\u{201d}").dsBody()
                            }
                        } else {
                            Text("\(partnerName) · 还没写").dsCaption()
                        }
                    }
                }

                if let body = moment.body, !body.isEmpty {
                    Text(body).dsBody()
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") { showEdit = true }
                    moveMenu
                    Button("删除", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $viewerIndex) { index in
            PhotoViewerView(photos: photos, index: index.id)
        }
        .sheet(isPresented: $showEdit) { MomentFormView(mode: .edit(moment)) }
        .sheet(isPresented: $showEvalForm) { EvaluationFormSheet(moment: moment) }
        .alert("删除这条记忆？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                do {
                    try MomentRepository(context: context).delete(moment)
                    dismiss()
                } catch {
                    deleteFailed = true
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("删除失败，请重试", isPresented: $deleteFailed) {
            Button("知道了", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var moveMenu: some View {
        if let meeting = moment.dateDay?.meeting,
           let days = try? MeetingRepository(context: context).daysSorted(in: meeting),
           days.count > 1 {
            Menu("移到其他日") {
                ForEach(days, id: \.objectID) { day in
                    if day.objectID != moment.dateDay?.objectID {
                        Button("第 \(day.dayIndex) 天") {
                            try? MomentRepository(context: context).move(moment, to: day)
                        }
                    }
                }
            }
        }
    }
}

private struct ViewerIndex: Identifiable {
    let id: Int
}
