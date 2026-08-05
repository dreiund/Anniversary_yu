import SwiftUI
import MapKit
import CoreData

/// 足迹·地图段（spec §四）：弱化底图 + 照片钉 + 屏幕空间聚合 + 七类筛选。
struct PlacesMapView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDPlace.createdAt)])
    private var places: FetchedResults<CDPlace>

    @State private var camera: MapCameraPosition = .automatic
    @State private var filter: PlaceCategory?          // nil = 全部
    @State private var selectedPlace: CDPlace?
    @State private var cameraTick = 0                  // 相机停稳后自增，触发聚合重算

    /// 有坐标且挂着记忆的地点，经筛选（spec §4.1）
    private var visiblePlaces: [CDPlace] {
        places.filter { p in
            (p.latitude != 0 || p.longitude != 0)
            && ((p.moments as? Set<CDMoment>)?.isEmpty == false)
            && (filter == nil || p.categoryRaw == filter!.rawValue)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterChips
            mapBody
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "全部", selected: filter == nil) { filter = nil }
                ForEach(PlaceCategory.allCases, id: \.rawValue) { cat in
                    chip(title: cat.label, selected: filter == cat) {
                        filter = filter == cat ? nil : cat
                    }
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
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(displayItems(proxy: proxy, tick: cameraTick), id: \.key) { item in
                    switch item.output {
                    case .pin(let id, _):
                        if let place = visiblePlaces.first(where: { $0.id == id }) {
                            Annotation("", coordinate: CLLocationCoordinate2D(
                                latitude: place.latitude, longitude: place.longitude)) {
                                PlacePin(image: place.latestThumbnail(context: context),
                                         fallbackText: place.name ?? "地")
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .stroke(DS.actionBlue,
                                                    lineWidth: selectedPlace == place ? 2 : 0)
                                            .padding(-2)
                                    )
                                    .onTapGesture { selectedPlace = place }
                            }
                        }
                    case .cluster(let ids, let point):
                        if let coord = proxy.convert(point, from: .local) {
                            Annotation("", coordinate: coord) {
                                Text("\(ids.count) 处")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 5).padding(.horizontal, 9)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(DS.darkCard))
                                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                                    .onTapGesture { zoomInto(coordinate: coord) }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { _ in
                cameraTick += 1
                }
            .onTapGesture { selectedPlace = nil }
            .overlay {
                if visiblePlaces.isEmpty {
                    Text("还没有带地点的记忆").dsCaption()
                }
            }
            .overlay(alignment: .bottom) {
                // 对方远端删除该地点时不渲染已删对象（spec §九，沿用 PlanView 守卫模式）
                if let selected = selectedPlace,
                   selected.managedObjectContext != nil, !selected.isDeleted {
                    PlaceDrawer(place: selected)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selectedPlace)
        }
    }

    /// 屏幕空间聚合：坐标→屏幕点→聚合→回投。ForEach 需要稳定 key。
    /// tick 参数只为在 body 求值期读到 cameraTick 注册依赖（MapContentBuilder 里不能写 let _）。
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
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 800, longitudinalMeters: 800))
        }
    }
}
