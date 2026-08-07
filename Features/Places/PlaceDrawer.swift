import SwiftUI
import CoreData

/// 点钉后的富抽屉（spec §4.2，小样选 B）：头行 + 两人均分墨条 + 最近照片条。
struct PlaceDrawer: View {
    @ObservedObject var place: CDPlace
    let onOpenProfile: () -> Void
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>

    private var placeMoments: [CDMoment] {
        ((place.moments as? Set<CDMoment>) ?? [])
            .sorted { ($0.happenedAt ?? .distantPast) > ($1.happenedAt ?? .distantPast) }
    }

    var body: some View {
        let repo = CoupleRepository(context: context)
        let momentRepo = MomentRepository(context: context)
        let me = couples.first.flatMap { repo.currentPartner(of: $0) }
        let other = couples.first.flatMap { repo.otherPartner(of: $0) }
        let myAvg = PlaceStats.average(placeMoments.compactMap { momentRepo.evaluation(of: $0, by: me?.id)?.stars })
        let otherAvg = PlaceStats.average(placeMoments.compactMap { momentRepo.evaluation(of: $0, by: other?.id)?.stars })
        let visits = PlaceStats.visitCount(dateDayIDs: placeMoments.map { $0.dateDay?.id })
        let lastDate = placeMoments.first?.happenedAt

        VStack(alignment: .leading, spacing: 9) {
            Button(action: onOpenProfile) {
                HStack(spacing: 9) {
                    Group {
                        if let img = place.latestThumbnail(context: context) {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            ZStack {
                                DS.parchment
                                Text(String((place.name ?? "地").prefix(1)))
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(DS.ink)
                            }
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.hairline, lineWidth: 1))
                    .allowsHitTesting(false)   // 溢出不抢头行链接点击
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(place.name ?? "未命名")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(DS.ink)
                            Text(PlaceCategory.from(raw: place.categoryRaw).label)
                                .font(.system(size: 9)).foregroundStyle(DS.actionBlue)
                                .padding(.vertical, 1).padding(.horizontal, 6)
                                .overlay(Capsule().stroke(DS.actionBlue, lineWidth: 1))
                        }
                        Text(subtitle(visits: visits, lastDate: lastDate)).dsFootnote().lineLimit(1)
                    }
                    Spacer()
                    Text("档案 ›").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.actionBlue)
                }
                .contentShape(Rectangle())   // 头像退出命中后，整行仍可点
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                scoreCell(label: "我的均分", value: myAvg)
                scoreCell(label: "\(other?.name ?? "TA")的均分", value: otherAvg)
            }

            // 照片条只收有照片的记忆；一张都没有就整条不显示（反馈：无照片占位方块不美观）
            let stripImages: [(CDMoment, UIImage)] = placeMoments.compactMap { moment in
                guard let data = momentRepo.photosSorted(moment).first?.thumbnailData,
                      let img = UIImage(data: data) else { return nil }
                return (moment, img)
            }
            if !stripImages.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(stripImages.prefix(3)), id: \.0.objectID) { _, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                            .allowsHitTesting(false)
                    }
                    if stripImages.count > 3 {
                        Text("+\(stripImages.count - 3)")
                            .font(.system(size: 10)).foregroundStyle(DS.inkMuted)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment))
                    }
                }
            }

            if place.latitude != 0 || place.longitude != 0 {
                Button {
                    AmapNavigator.navigate(name: place.name ?? "目的地",
                                           latitude: place.latitude, longitude: place.longitude)
                } label: {
                    Text("导航到这里 ›")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.actionBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(DS.parchment))
                }
                .buttonStyle(DSPressEffect())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.large).fill(DS.canvas))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        .padding(.horizontal, 8)
    }

    private func subtitle(visits: Int, lastDate: Date?) -> String {
        var parts: [String] = []
        if let addr = place.address, !addr.isEmpty { parts.append(addr) }
        parts.append("来过 \(visits) 次")
        if let lastDate { parts.append("上次 \(Fmt.monthDay.string(from: lastDate))") }
        // 该地点对我可见的小本本条数（私密过滤同地图钉判定）
        let myID = couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
        let ledgerCount = ((place.ledgerEntries as? Set<CDLedgerEntry>) ?? []).filter {
            LedgerRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                  visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }.count
        if ledgerCount > 0 { parts.append("小本本 \(ledgerCount) 条") }
        return parts.joined(separator: " · ")
    }

    private func scoreCell(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundStyle(DS.inkMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.hairline)
                    if let value {
                        Capsule().fill(DS.ink).frame(width: geo.size.width * min(value / 5.0, 1))
                    }
                }
            }
            .frame(height: 4)
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(DS.ink)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.parchment))
        .frame(maxWidth: .infinity)
    }

}
