import SwiftUI
import MapKit
import CoreData

/// 足迹地图的筛选：全部 / 七类 / 小本本（与类目并列，反馈需求）
enum PlacesMapFilter: Hashable {
    case all
    case category(PlaceCategory)
    case ledger
}

/// 足迹·地图段（spec §四）：弱化底图 + 照片钉 + 屏幕空间聚合 + 七类筛选 + 小本本筛选。
struct PlacesMapView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDPlace.createdAt)])
    private var places: FetchedResults<CDPlace>
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>

    @State private var camera: MapCameraPosition = .automatic
    @State private var filter: PlacesMapFilter = .all
    @State private var selectedPlace: CDPlace?
    @State private var profilePlace: CDPlace?   // 程序化推档案：目标页在正常视图环境构建，不进 Map overlay 的链接邪路
    @State private var cameraTick = 0                  // 相机停稳后自增，触发聚合重算
    @State private var currentRegion: MKCoordinateRegion?

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

    /// 有坐标、且挂着记忆或可见小本本条目的地点，经筛选（spec §4.1 + 反馈扩展）
    private var visiblePlaces: [CDPlace] {
        places.filter { p in
            guard p.latitude != 0 || p.longitude != 0 else { return false }
            let hasMoments = (p.moments as? Set<CDMoment>)?.isEmpty == false
            let hasLedger = hasVisibleLedger(p)
            guard hasMoments || hasLedger else { return false }
            switch filter {
            case .all: return true
            case .category(let cat): return p.categoryRaw == cat.rawValue
            case .ledger: return hasLedger
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterChips
            mapBody
        }
        .onChange(of: filter) {
            if let selected = selectedPlace, !visiblePlaces.contains(selected) {
                selectedPlace = nil
            }
            // 取景规则（用户定稿）：空类目或新集合全在当前视野内 → 区域不动只换钉；
            // 新集合在视野外（如广州→苏州）→ 平滑飞过去
            guard let target = boundingRegion(of: visiblePlaces) else { return }
            if let current = currentRegion, contains(current, allOf: visiblePlaces) { return }
            withAnimation(.smooth(duration: 0.8)) { camera = .region(target) }
        }
        .navigationDestination(item: $profilePlace) { place in
            PlaceProfileView(place: place)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "全部", selected: filter == .all) { filter = .all }
                ForEach(PlaceCategory.allCases, id: \.rawValue) { cat in
                    chip(title: cat.label, selected: filter == .category(cat)) {
                        filter = filter == .category(cat) ? .all : .category(cat)
                    }
                }
                chip(title: "小本本", selected: filter == .ledger) {
                    filter = filter == .ledger ? .all : .ledger
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
        MapReader { proxy in
            Map(position: $camera)
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .continuous) { context in
                currentRegion = context.region
                cameraTick += 1
                }
            .onTapGesture { selectedPlace = nil }
            .overlay { pinLayer(proxy: proxy).clipped() }
            .overlay {
                if visiblePlaces.isEmpty {
                    Text("还没有带地点的记忆").dsCaption()
                }
            }
            .onAppear {
                if currentRegion == nil, let region = boundingRegion(of: visiblePlaces) {
                    camera = .region(region)
                }
            }
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
    }

    /// 钉层：屏幕坐标直渲（普通 ViewBuilder，筛选/相机变化即时重投）。
    /// 动画只绑 filter——切筛选淡入淡出；拖拽缩放的连续重投不做动画（跟手优先）。
    @ViewBuilder
    private func pinLayer(proxy: MapProxy) -> some View {
        let _ = cameraTick   // 连续重投影依赖注册
        ZStack {
            ForEach(displayItems(proxy: proxy, tick: cameraTick), id: \.key) { item in
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
                                // 小本本角标：与记忆钉在图上区分（反馈需求）
                                if hasVisibleLedger(place) {
                                    Text("本")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 13, height: 13)
                                        .background(Circle().fill(DS.ink))
                                        .overlay(Circle().stroke(.white, lineWidth: 1))
                                        .offset(x: 4, y: 4)
                                        .allowsHitTesting(false)
                                }
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
                            if let coord = proxy.convert(point, from: .local) {
                                zoomInto(coordinate: coord)
                            }
                        }
                        .position(point)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.smooth, value: filter)
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
    private func displayItems(proxy: MapProxy, tick: Int) -> [(key: String, output: ClusterOutput)] {
        let inputs = visiblePlaces.compactMap { place -> ClusterInput? in
            guard let id = place.id,
                  let pt = proxy.convert(CLLocationCoordinate2D(latitude: place.latitude,
                                                                longitude: place.longitude),
                                         to: .local) else { return nil }
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
