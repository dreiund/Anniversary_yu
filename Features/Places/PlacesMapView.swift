import SwiftUI
import MapKit
import CoreData

/// 足迹地图的筛选：全部 / 七类 / 小本本 / 计划 / 记得做（反馈⑦扩展）
enum PlacesMapFilter: Hashable {
    case all
    case category(PlaceCategory)
    case ledger
    case plans
    case todos
}

/// 足迹·地图段（spec §四）：弱化底图 + 照片钉 + 屏幕空间聚合 + 七类筛选 + 小本本筛选。
struct PlacesMapView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDPlace.createdAt)])
    private var places: FetchedResults<CDPlace>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>

    @State private var camera: MapCameraPosition = .automatic
    @State private var filter: PlacesMapFilter = .all
    @State private var meetingIndex: Int32?          // 反馈⑦ 3A：按第几次见面筛选，nil=全部
    @State private var selectedPlace: CDPlace?
    @State private var profilePlace: CDPlace?   // 程序化推档案：目标页在正常视图环境构建，不进 Map overlay 的链接邪路
    @State private var currentRegion: MKCoordinateRegion?   // 相机事件的实际可见区域
    @State private var fittedRegion: MKCoordinateRegion?     // 我们主动取景的目标区域（首帧投影兜底）
    @State private var didInitialFit = false           // 反馈⑦：初始取景只认这面旗

    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }

    /// 地点是否含对我可见的小本本条目（私密过滤不旁路：只挂对方私密条目的地点隐形）
    private func hasVisibleLedger(_ place: CDPlace) -> Bool {
        let entries = ((place.ledgerEntries as? Set<CDLedgerEntry>) ?? []).map {
            (authorID: $0.authorPartnerID, visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        return LedgerRules.anyVisible(myID: myID, entries: entries)
    }

    /// 计划钉（反馈⑦ 1A）：挂着未结束见面日程的地点——见面结束即从地图消失（数据保留）
    /// 反馈⑨终审(M-1):备忘(day == nil)已独立出计划流水线(时间线左缘侧签,永不转化为日程)，
    /// 不算「计」的口径内，排除在外——否则备忘会在地图上误出「计」钉
    private func hasActivePlan(_ place: CDPlace) -> Bool {
        ((place.planItems as? Set<CDPlanItem>) ?? []).contains {
            guard $0.day != nil, let meeting = $0.meeting else { return false }
            return meeting.statusRaw != MeetingStatus.finished.rawValue
        }
    }

    /// 记得做钉（反馈⑦ 2A）：仅未完成且对我可见的（隐私沿用小本本规则，做完即从地图消失）
    private func hasVisibleTodo(_ place: CDPlace) -> Bool {
        ((place.todoItems as? Set<CDTodoItem>) ?? []).contains {
            !$0.isDone && TodoRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                              visibilityRaw: $0.visibilityRaw,
                                              revealedAt: $0.revealedAt)
        }
    }

    private func matchesMeeting(_ place: CDPlace, index: Int32) -> Bool {
        ((place.moments as? Set<CDMoment>) ?? []).contains {
            $0.dateDay?.meeting?.index == index
        }
    }

    /// 有坐标、且挂着记忆/可见小本本/未结束计划/未完成记得做的地点，经筛选（spec §4.1 + 反馈⑦）
    private var visiblePlaces: [CDPlace] {
        places.filter { p in
            guard p.latitude != 0 || p.longitude != 0 else { return false }
            let hasMoments = (p.moments as? Set<CDMoment>)?.isEmpty == false
            // 3A：选定具体见面＝只看该次记忆钉，小本本/计划/记得做钉隐藏
            if let index = meetingIndex {
                guard hasMoments, matchesMeeting(p, index: index) else { return false }
                switch filter {
                case .all: return true
                case .category(let cat): return cat.mergedRaws.contains(p.categoryRaw)
                case .ledger, .plans, .todos: return false
                }
            }
            let hasLedger = hasVisibleLedger(p)
            // 「计划」筛选 chip(.plans)与角标钉同复用 hasActivePlan，已含 day != nil 排除备忘，
            // 口径天然一致，无需在此再叠加过滤（反馈⑨终审 M-1）
            let hasPlan = hasActivePlan(p)
            let hasTodo = hasVisibleTodo(p)
            guard hasMoments || hasLedger || hasPlan || hasTodo else { return false }
            switch filter {
            case .all: return true
            case .category(let cat): return cat.mergedRaws.contains(p.categoryRaw)
            case .ledger: return hasLedger
            case .plans: return hasPlan
            case .todos: return hasTodo
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterChips
            mapBody
        }
        .onChange(of: filter) { retargetCamera() }
        .navigationDestination(item: $profilePlace) { place in
            PlaceProfileView(place: place)
        }
    }

    private func initialFitIfNeeded() {
        guard !didInitialFit, let region = boundingRegion(of: visiblePlaces) else { return }
        didInitialFit = true
        fittedRegion = region
        withAnimation(.smooth(duration: 0.6)) { camera = .region(region) }
    }

    /// 取景规则（用户定稿）：空集合或新集合全在当前视野内 → 区域不动只换钉；
    /// 新集合在视野外（如广州→苏州）→ 平滑飞过去
    private func retargetCamera() {
        if let selected = selectedPlace, !visiblePlaces.contains(selected) {
            selectedPlace = nil
        }
        guard let target = boundingRegion(of: visiblePlaces) else { return }
        if let current = currentRegion, contains(current, allOf: visiblePlaces) { return }
        fittedRegion = target
        withAnimation(.smooth(duration: 0.8)) { camera = .region(target) }
    }

    /// 按第几次见面筛选（反馈⑦ 3A）：与类目叠加；选定具体见面时小本本/计划/记得做筛选回落「全部」
    private var meetingMenu: some View {
        Menu {
            Button("全部见面") { selectMeeting(nil) }
            // 反馈⑬④:还没开始的见面(planned)不算「一次见面」,不进按次筛选
            ForEach(meetings.filter { $0.statusRaw != MeetingStatus.planned.rawValue }, id: \.objectID) { m in
                Button("第 \(m.index) 次见面") { selectMeeting(m.index) }
            }
        } label: {
            Text(meetingIndex.map { "第 \($0) 次 ▾" } ?? "全部见面 ▾")
                .font(.system(size: 12, weight: meetingIndex != nil ? .semibold : .regular))
                .foregroundStyle(meetingIndex != nil ? .white : DS.ink)
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Capsule().fill(meetingIndex != nil ? DS.actionBlue : DS.canvas))
                .overlay(Capsule().stroke(meetingIndex != nil ? DS.actionBlue : DS.chipBorder,
                                          lineWidth: 1))
        }
    }

    private func selectMeeting(_ index: Int32?) {
        meetingIndex = index
        if index != nil, [.ledger, .plans, .todos].contains(filter) { filter = .all }
        retargetCamera()
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                meetingMenu
                chip(title: "全部", selected: filter == .all) { filter = .all }
                ForEach(PlaceCategory.displayCases, id: \.rawValue) { cat in
                    chip(title: cat.label, selected: filter == .category(cat)) {
                        filter = filter == .category(cat) ? .all : .category(cat)
                    }
                }
                chip(title: "小本本", selected: filter == .ledger) {
                    filter = filter == .ledger ? .all : .ledger
                }
                chip(title: "计划", selected: filter == .plans) {
                    filter = filter == .plans ? .all : .plans
                }
                chip(title: "待办", selected: filter == .todos) {
                    filter = filter == .todos ? .all : .todos
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 6)
        }
        .background(DS.canvas)
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : DS.ink)
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Capsule().fill(selected ? DS.actionBlue : DS.canvas))
                .overlay(Capsule().stroke(selected ? DS.actionBlue : DS.chipBorder, lineWidth: 1))
        }
        .buttonStyle(DSPressEffect())
    }

    private var mapBody: some View {
        // 钉层不进 Map 内容（MapContentBuilder 延迟求值不追踪外部状态，筛选切换会残留旧钉——
        // 反馈⑤截图实证）；改为屏幕坐标 overlay 直渲，与路线图同款：即时响应、可动画、相机不被动
        Map(position: $camera)
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .continuous) { context in
                currentRegion = context.region
            }
            .onTapGesture { selectedPlace = nil }
            .overlay { GeometryReader { geo in pinLayer(size: geo.size).clipped() } }
            .overlay {
                if visiblePlaces.isEmpty {
                    Text("还没有带地点的记忆").dsCaption()
                }
            }
            .onAppear { initialFitIfNeeded() }
            // 真机上相机回调常先于 onAppear 把 currentRegion 占住，旧的「currentRegion 为空才取景」
            // 会永远不飞——bug3 元凶（真机全国图无钉）。改为一次性旗标 + 数据迟到重试（CloudKit 首启）
            .onChange(of: places.count) { initialFitIfNeeded() }
            .overlay(alignment: .bottom) {
                // 对方远端删除该地点时不渲染已删对象（spec §九，沿用 PlanView 守卫模式）
                if let selected = selectedPlace,
                   selected.managedObjectContext != nil, !selected.isDeleted {
                    PlaceDrawer(place: selected, onOpenProfile: { profilePlace = selected })
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selectedPlace)
    }

    private func pinBadge(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(.white, lineWidth: 1))
    }

    /// 钉层（反馈⑧bug1 架构重写）：弃 MapProxy.convert——其首帧就绪时机不可控且失败后
    /// 子树可能不再重投（探针多轮实证）。改为 currentRegion（相机事件）∥ fittedRegion（主动取景）
    /// + 墨卡托纯数学投影：首帧即确定性可算，与 Map 内部状态彻底解耦。
    /// 动画只绑 filter——切筛选淡入淡出；拖拽缩放的连续重投不做动画（跟手优先）。
    @ViewBuilder
    private func pinLayer(size: CGSize) -> some View {
        let region = currentRegion ?? fittedRegion
        let items = displayItems(size: size)
        ZStack {
            ForEach(items, id: \.key) { item in
                switch item.output {
                case .pin(let id, let point):
                    if let place = visiblePlaces.first(where: { $0.id == id }) {
                        PlacePin(image: place.latestThumbnail(context: context),
                                 fallbackText: place.name ?? "地")
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(DS.actionBlue,
                                            lineWidth: selectedPlace == place ? 2 : 0)
                                    .padding(-2)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                // 角标簇：小本本墨「本」/ 计划蓝「计」/ 记得做蓝「做」（反馈⑦）
                                HStack(spacing: 2) {
                                    if hasVisibleLedger(place) { pinBadge("本", fill: DS.ink) }
                                    if hasActivePlan(place) { pinBadge("计", fill: DS.actionBlue) }
                                    if hasVisibleTodo(place) { pinBadge("做", fill: DS.actionBlue) }
                                }
                                .offset(x: 4, y: 4)
                                .allowsHitTesting(false)
                            }
                            .onTapGesture { selectedPlace = place }
                            .position(point)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                case .cluster(let ids, let point):
                    Text("\(ids.count) 处")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 5).padding(.horizontal, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DS.darkCard))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        .onTapGesture {
                            if let region {
                                zoomInto(coordinate: inverseProject(point, in: region, size: size))
                            }
                        }
                        .position(point)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.smooth, value: filter)
    }

    private var projectionRegion: MKCoordinateRegion? { currentRegion ?? fittedRegion }

    /// Web-Mercator 投影：region（相机事件给的实际可见区域）→ 屏幕点
    private func project(_ coord: CLLocationCoordinate2D, in region: MKCoordinateRegion,
                         size: CGSize) -> CGPoint {
        let left = region.center.longitude - region.span.longitudeDelta / 2
        let x = (coord.longitude - left) / region.span.longitudeDelta * size.width
        let top = mercY(region.center.latitude + region.span.latitudeDelta / 2)
        let bottom = mercY(region.center.latitude - region.span.latitudeDelta / 2)
        let y = (top - mercY(coord.latitude)) / (top - bottom) * size.height
        return CGPoint(x: x, y: y)
    }

    private func inverseProject(_ point: CGPoint, in region: MKCoordinateRegion,
                                size: CGSize) -> CLLocationCoordinate2D {
        let left = region.center.longitude - region.span.longitudeDelta / 2
        let lon = left + Double(point.x / size.width) * region.span.longitudeDelta
        let top = mercY(region.center.latitude + region.span.latitudeDelta / 2)
        let bottom = mercY(region.center.latitude - region.span.latitudeDelta / 2)
        let merc = top - Double(point.y / size.height) * (top - bottom)
        let lat = (2 * atan(exp(merc)) - .pi / 2) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func mercY(_ lat: Double) -> Double {
        let phi = max(min(lat, 85.0), -85.0) * .pi / 180
        return log(tan(.pi / 4 + phi / 2))
    }

    private func displayItems(size: CGSize) -> [(key: String, output: ClusterOutput)] {
        guard let region = projectionRegion, size.width > 0, size.height > 0 else { return [] }
        let inputs = visiblePlaces.compactMap { place -> ClusterInput? in
            guard let id = place.id else { return nil }
            let pt = project(CLLocationCoordinate2D(latitude: place.latitude,
                                                    longitude: place.longitude),
                             in: region, size: size)
            return ClusterInput(id: id, point: pt)
        }
        return MapClusterer.cluster(inputs, threshold: 44).map { out in
            switch out {
            case .pin(let id, _): return (key: "p-\(id)", output: out)
            case .cluster(let ids, _):
                return (key: "c-" + ids.map(\.uuidString).sorted().joined(separator: "-"), output: out)
            }
        }
    }

    /// 可见地点的取景边界（1.5 倍留白，最小跨度兜底）；空集合返回 nil
    private func boundingRegion(of places: [CDPlace]) -> MKCoordinateRegion? {
        guard !places.isEmpty else { return nil }
        let lats = places.map(\.latitude), lons = places.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.02),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.02))
        return MKCoordinateRegion(center: center, span: span)
    }

    /// 集合是否全部落在当前视野内（在则筛选切换不动相机）
    private func contains(_ region: MKCoordinateRegion, allOf places: [CDPlace]) -> Bool {
        places.allSatisfy { p in
            abs(p.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && abs(p.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
        }
    }

    /// 屏幕空间聚合：坐标→屏幕点→聚合。ForEach 需要稳定 key。

    private func zoomInto(coordinate: CLLocationCoordinate2D) {
        withAnimation(.smooth) {
            if let currentRegion {
                let span = currentRegion.span
                camera = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta / 2,
                                          longitudeDelta: span.longitudeDelta / 2)))
            } else {
                camera = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 800, longitudinalMeters: 800))
            }
        }
    }
}
