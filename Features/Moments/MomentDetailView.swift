import SwiftUI

struct MomentDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let moment: CDMoment
    @State private var viewerIndex: ViewerIndex?
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false

    var body: some View {
        let repo = MomentRepository(context: context)
        let photos = repo.photosSorted(moment)
        let couples = CoupleRepository(context: context)
        let partners = (try? couples.fetchCouple()).map { couples.partners(of: $0) } ?? []
        let myEval = partners.first.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = partners.count > 1 ? (partners[1].name ?? "TA") : "TA"

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
                                Text("“\(comment)”").dsBody()
                            }
                        } else {
                            Text("你还没写评价").dsCaption()
                        }
                        DS.hairline.frame(height: 1)
                        Text("\(partnerName) · 还没写（P2 同步后她可以补上）").dsFootnote()
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
        .confirmationDialog("删除这条记忆？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do {
                    try MomentRepository(context: context).delete(moment)
                    dismiss()
                } catch {
                    deleteFailed = true
                }
            }
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
