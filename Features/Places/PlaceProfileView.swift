import SwiftUI
import MapKit
import CoreData

/// 地点档案（spec §五）：圆照片头 + 统计三格 + 按见面分组历史。
struct PlaceProfileView: View {
    @ObservedObject var place: CDPlace
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @State private var showCategoryPicker = false
    @State private var showMiniMap = false

    private var placeMoments: [CDMoment] {
        ((place.moments as? Set<CDMoment>) ?? [])
            .sorted { ($0.happenedAt ?? .distantPast) > ($1.happenedAt ?? .distantPast) }
    }

    private var partnerIDs: (me: UUID?, other: UUID?, otherName: String) {
        let repo = CoupleRepository(context: context)
        guard let couple = couples.first else { return (nil, nil, "TA") }
        let other = repo.otherPartner(of: couple)
        return (repo.currentPartner(of: couple)?.id, other?.id, other?.name ?? "TA")
    }

    private func stars(by author: UUID?) -> [Int16] {
        let repo = MomentRepository(context: context)
        return placeMoments.compactMap { repo.evaluation(of: $0, by: author)?.stars }
    }

    var body: some View {
        if place.managedObjectContext == nil || place.isDeleted {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        let ids = partnerIDs
        let myAvg = PlaceStats.average(stars(by: ids.me))
        let otherAvg = PlaceStats.average(stars(by: ids.other))
        let visits = PlaceStats.visitCount(dateDayIDs: placeMoments.map { $0.dateDay?.id })
        return ScrollView {
            VStack(spacing: DS.Spacing.sm) {
                header
                HStack(spacing: 8) {
                    statCard(label: "来过", value: "\(visits) 次", bar: nil)
                    statCard(label: "我的均分",
                             value: myAvg.map { String(format: "%.1f", $0) } ?? "—",
                             bar: myAvg)
                    statCard(label: "\(ids.otherName)的均分",
                             value: otherAvg.map { String(format: "%.1f", $0) } ?? "—",
                             bar: otherAvg)
                }
                Button("在地图中查看 ›") { showMiniMap = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.actionBlue)
                historyList
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle(place.name ?? "地点")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCategoryPicker) { categoryPicker }
        .sheet(isPresented: $showMiniMap) { miniMap }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Group {
                if let img = place.latestThumbnail(context: context) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        DS.parchment
                        Text(String((place.name ?? "地").prefix(1)))
                            .font(.system(size: 24, weight: .bold)).foregroundStyle(DS.ink)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 5, y: 3)

            HStack(spacing: 6) {
                Text(place.name ?? "未命名").font(.system(size: 17, weight: .bold))
                Button {
                    showCategoryPicker = true
                } label: {
                    Text(PlaceCategory.from(raw: place.categoryRaw).label)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.actionBlue)
                        .padding(.vertical, 2).padding(.horizontal, 8)
                        .overlay(Capsule().stroke(DS.actionBlue, lineWidth: 1))
                }
                .buttonStyle(DSPressEffect())
            }
            if let addr = place.address, !addr.isEmpty {
                Text(addr).dsFootnote()
            }
        }
    }

    private func statCard(label: String, value: String, bar: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(DS.inkMuted)
            Text(value).font(.system(size: 15, weight: .bold))
            if let bar {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.hairline)
                        Capsule().fill(DS.ink)
                            .frame(width: geo.size.width * min(bar / 5.0, 1))
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))
    }

    /// 按见面分组（spec §五，小样选 A）：组头「第 n 次见面 · 起–止 ›」跳见面详情
    private var historyList: some View {
        let groups = Dictionary(grouping: placeMoments) { $0.dateDay?.meeting }
            .compactMap { (meeting, moments) -> (CDMeeting, [CDMoment])? in
                guard let meeting else { return nil }
                return (meeting, moments)
            }
            .sorted { $0.0.index > $1.0.index }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(groups, id: \.0.objectID) { meeting, moments in
                NavigationLink { MeetingDetailView(meeting: meeting) } label: {
                    Text("\(groupTitle(meeting)) ›")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.inkMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(moments, id: \.objectID) { moment in
                        historyRow(moment)
                        if moment != moments.last {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))
            }
        }
    }

    private func groupTitle(_ meeting: CDMeeting) -> String {
        var range = ""
        if let s = meeting.startedAt {
            range = " · " + Fmt.ymd.string(from: s)
            if let e = meeting.endedAt {
                let cal = Calendar.current
                range += "–\(cal.component(.day, from: e))"
            }
        }
        return "第 \(meeting.index) 次见面\(range)"
    }

    private func historyRow(_ moment: CDMoment) -> some View {
        let repo = MomentRepository(context: context)
        let ids = partnerIDs
        let thumb = repo.photosSorted(moment).first?.thumbnailData.flatMap(UIImage.init(data:))
        let mine = repo.evaluation(of: moment, by: ids.me)?.stars
        let theirs = repo.evaluation(of: moment, by: ids.other)?.stars
        let sub = [moment.happenedAt.map { "\(Fmt.monthDay.string(from: $0)) \(Fmt.hm.string(from: $0))" }]
            .compactMap { $0 }.joined()
        return NavigationLink { MomentDetailView(moment: moment) } label: {
            HStack(spacing: 10) {
                Group {
                    if let thumb {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                .allowsHitTesting(false)   // 溢出不抢相邻行点击
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title ?? "未命名").dsBody().lineLimit(1)
                    Text(sub).dsFootnote()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let mine { Text("我 ★\(mine)") }
                    if let theirs { Text("\(ids.otherName) ★\(theirs)") }
                }
                .font(.system(size: 9))
                .foregroundStyle(DS.ink)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var categoryPicker: some View {
        NavigationStack {
            List(PlaceCategory.allCases, id: \.rawValue) { cat in
                Button {
                    place.categoryRaw = cat.rawValue
                    try? context.save()
                    showCategoryPicker = false
                } label: {
                    HStack {
                        Text(cat.label).dsBody()
                        Spacer()
                        if place.categoryRaw == cat.rawValue {
                            Image(systemName: "checkmark").font(.system(size: 12))
                                .foregroundStyle(DS.actionBlue)
                        }
                    }
                }
            }
            .navigationTitle("改分类")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var miniMap: some View {
        NavigationStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                latitudinalMeters: 600, longitudinalMeters: 600))) {
                Annotation("", coordinate: CLLocationCoordinate2D(
                    latitude: place.latitude, longitude: place.longitude)) {
                    PlacePin(image: place.latestThumbnail(context: context),
                             fallbackText: place.name ?? "地")
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .navigationTitle(place.name ?? "地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showMiniMap = false }
                }
            }
        }
    }
}
