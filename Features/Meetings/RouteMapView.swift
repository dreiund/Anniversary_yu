import SwiftUI
import MapKit
import CoreData

/// 见面路线图（spec §六）：编号照片钉 + 行动蓝虚线弧连 + 天数筛选 + 播放生长。
struct RouteMapView: View {
    let meeting: CDMeeting
    @Environment(\.managedObjectContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedDay: Int32?          // nil = 全部
    @State private var progress: CGFloat = 1        // 虚线 trim 进度，默认全显
    @State private var playing = false
    @State private var cameraTick = 0

    private var routeDays: [RouteDay] {
        let repo = MomentRepository(context: context)
        let inputs = repo.daysWithMoments(in: meeting).flatMap { day, moments in
            moments.compactMap { m -> RouteStopInput? in
                guard let id = m.id, let place = m.place,
                      place.latitude != 0 || place.longitude != 0,
                      let at = m.happenedAt else { return nil }
                return RouteStopInput(momentID: id, dayIndex: day.dayIndex, happenedAt: at,
                                      latitude: place.latitude, longitude: place.longitude)
            }
        }
        return RouteBuilder.days(from: inputs)
    }

    private var visibleDays: [RouteDay] {
        guard let selectedDay else { return routeDays }
        return routeDays.filter { $0.dayIndex == selectedDay }
    }

    var body: some View {
        let days = routeDays
        VStack(spacing: 0) {
            if days.isEmpty {
                Text("这次见面还没有带地点的记忆").dsCaption()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.parchment)
            } else {
                dayChips(days)
                routeMap
            }
        }
        .onAppear { fitCamera() }
        .onChange(of: selectedDay) { fitCamera() }
    }

    private func dayChips(_ days: [RouteDay]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                SelectableChip(title: "全部", isSelected: selectedDay == nil) { selectedDay = nil }
                ForEach(days, id: \.dayIndex) { day in
                    SelectableChip(title: "D\(day.dayIndex)",
                                   isSelected: selectedDay == day.dayIndex) {
                        selectedDay = day.dayIndex
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 6)
        }
        .background(DS.parchment)
    }

    private var routeMap: some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(visibleDays, id: \.dayIndex) { day in
                    ForEach(day.stops, id: \.momentID) { stop in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: stop.latitude, longitude: stop.longitude)) {
                            stopPin(stop)
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { _ in cameraTick += 1 }
            .overlay {
                let _ = cameraTick   // 相机变化后重投屏幕点
                routeLines(proxy: proxy)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) { playButton }
        }
    }

    private func stopPin(_ stop: RouteStop) -> some View {
        let moment = fetchMoment(stop.momentID)
        let thumb = moment.flatMap {
            MomentRepository(context: context).photosSorted($0).first?.thumbnailData
        }.flatMap(UIImage.init(data:))
        return PlacePin(image: thumb, fallbackText: moment?.title ?? "点", size: 32)
            .overlay(alignment: .topLeading) {
                Text("\(stop.order)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(DS.actionBlue))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: -6, y: -6)
            }
    }

    private func fetchMoment(_ id: UUID) -> CDMoment? {
        let req = NSFetchRequest<CDMoment>(entityName: "CDMoment")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    /// 每天一条 trim 虚线；「全部」模式各天各画各的，天与天之间不连（spec §六）。
    private func routeLines(proxy: MapProxy) -> some View {
        ForEach(visibleDays, id: \.dayIndex) { day in
            let points = day.stops.compactMap {
                proxy.convert(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                              to: .local)
            }
            if points.count >= 2 {
                RoutePath(points: points)
                    .trim(from: 0, to: progress)
                    .stroke(DS.actionBlue,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
            }
        }
    }

    private var playButton: some View {
        Button {
            if playing { stopPlay() } else { play() }
        } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(DS.actionBlue))
                .shadow(color: DS.actionBlue.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(DSPressEffect())
        .padding(.trailing, 14).padding(.bottom, 16)
        .accessibilityLabel(playing ? "停止" : "播放路线")
    }

    private func play() {
        let segmentCount = visibleDays.map { max($0.stops.count - 1, 0) }.reduce(0, +)
        guard segmentCount > 0 else { return }
        playing = true
        progress = 0
        let duration = reduceMotion ? 0 : 0.5 * Double(segmentCount)
        withAnimation(.linear(duration: duration)) { progress = 1 }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            playing = false
        }
    }

    private func stopPlay() {
        withAnimation(.linear(duration: 0)) { progress = 1 }
        playing = false
    }

    private func fitCamera() {
        let stops = visibleDays.flatMap(\.stops)
        guard !stops.isEmpty else { return }
        let lats = stops.map(\.latitude), lons = stops.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.008),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.008))
        withAnimation(.smooth) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

/// 相邻站点二次贝塞尔弧连（控制点取中点垂线偏移，弧度克制）。
struct RoutePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])
        for i in 1..<points.count {
            let from = points[i - 1], to = points[i]
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let dx = to.x - from.x, dy = to.y - from.y
            let len = max(hypot(dx, dy), 0.001)
            let lift = min(len * 0.18, 26)
            let control = CGPoint(x: mid.x - dy / len * lift, y: mid.y + dx / len * lift)
            path.addQuadCurve(to: to, control: control)
        }
        return path
    }
}
