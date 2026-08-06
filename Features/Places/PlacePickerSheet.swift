import SwiftUI
import MapKit
import CoreData

struct PickedPlace: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var categoryRaw: Int16 = 0
    var existingPlaceID: UUID? = nil
}

/// 记忆地点的地图选点：搜索 / 地图落点 / 一键定位 三合一。
/// 只回传 PickedPlace 值；CDPlace 的创建由调用方负责（保持六字段纪律）。
struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PickedPlace?
    let onPick: (PickedPlace) -> Void

    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var lastAutoName = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var locating = false
    @State private var visibleRegion: MKCoordinateRegion?

    @FetchRequest(sortDescriptors: [SortDescriptor(\CDPlace.createdAt)])
    private var existingPlaces: FetchedResults<CDPlace>
    @State private var categoryRaw: Int16 = 0
    @State private var linkedPlaceID: UUID?
    @State private var mergeCandidate: PickedPlace?   // 兜底弹窗待确认的新建值
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(name.isEmpty ? "所选地点" : name, coordinate: pin)
                            .tint(DS.actionBlue)
                    }
                    ForEach(existingPlaces.filter {
                        ($0.latitude != 0 || $0.longitude != 0) && $0.id != linkedPlaceID
                    }, id: \.objectID) { place in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: place.latitude, longitude: place.longitude)) {
                            PlacePin(image: place.latestThumbnail(context: context),
                                     fallbackText: place.name ?? "地", size: 22)
                                .onTapGesture { adopt(place) }
                        }
                    }
                }
                .onTapGesture { point in
                    guard let coord = proxy.convert(point, from: .local) else { return }
                    drop(at: coord, refillAutoName: true)
                }
                .onMapCameraChange { context in
                    visibleRegion = context.region
                }
            }
            .overlay(alignment: .top) { searchOverlay }
            .safeAreaInset(edge: .bottom) { confirmBar }
            .navigationTitle("选地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear { restoreInitial() }
            .alert("是上次那家「\(mergeHitName)」吗？",
                   isPresented: Binding(get: { mergeCandidate != nil },
                                        set: { if !$0 { mergeCandidate = nil } })) {
                Button("就是这家") {
                    if let candidate = mergeCandidate {
                        onPick(candidate)      // existingPlaceID 已填，关联既有
                        dismiss()
                    }
                }
                Button("新建地点") {
                    if var candidate = mergeCandidate {
                        candidate.existingPlaceID = nil
                        onPick(candidate)
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) { mergeCandidate = nil }
            } message: {
                Text("50 米内有你们来过的地点，关联后来过几次和评分会记在同一家。")
            }
        }
    }

    private var searchOverlay: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("搜索地点", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                Button("搜索") { runSearch() }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.actionBlue)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(DS.canvas))
            .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { i, item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "未命名").font(.system(size: 15)).foregroundStyle(DS.ink)
                                if let addr = item.placemark.title {
                                    Text(addr).font(.system(size: 11)).foregroundStyle(DS.inkMuted).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if i < min(results.count, 5) - 1 {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, DS.Spacing.md).padding(.top, 8)
    }

    private var confirmBar: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("地点名称", text: $name)
                    .textFieldStyle(.plain)
                Button(locating ? "定位中" : "定位") { locateMe() }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.actionBlue)
                    .disabled(locating)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))

            if linkedPlaceID == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(PlaceCategory.allCases, id: \.rawValue) { cat in
                            Button {
                                categoryRaw = cat.rawValue
                            } label: {
                                Text(cat.label)
                                    .font(.system(size: 11,
                                                  weight: categoryRaw == cat.rawValue ? .semibold : .regular))
                                    .foregroundStyle(categoryRaw == cat.rawValue ? .white : DS.ink)
                                    .padding(.vertical, 3).padding(.horizontal, 9)
                                    .background(Capsule().fill(
                                        categoryRaw == cat.rawValue ? DS.actionBlue : DS.canvas))
                                    .overlay(Capsule().stroke(
                                        categoryRaw == cat.rawValue ? DS.actionBlue : DS.chipBorder,
                                        lineWidth: 1))
                            }
                            .buttonStyle(DSPressEffect())
                        }
                    }
                }
            }

            Button("保存") {
                guard let pin else { return }
                let picked = PickedPlace(name: name.trimmingCharacters(in: .whitespaces),
                                         latitude: pin.latitude, longitude: pin.longitude,
                                         categoryRaw: categoryRaw,
                                         existingPlaceID: linkedPlaceID)
                if picked.existingPlaceID == nil,
                   let hit = existingPlaces.first(where: {
                       ($0.latitude != 0 || $0.longitude != 0) && PlaceMergeRule.isCandidate(
                           name: picked.name, latitude: picked.latitude, longitude: picked.longitude,
                           existingName: $0.name ?? "",
                           existingLatitude: $0.latitude, existingLongitude: $0.longitude)
                   }) {
                    mergeCandidate = PickedPlace(name: picked.name,
                                                 latitude: picked.latitude, longitude: picked.longitude,
                                                 categoryRaw: picked.categoryRaw,
                                                 existingPlaceID: hit.id)
                    return
                }
                onPick(picked)
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .disabled(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, DS.Spacing.md).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// 名字仍是"自动填入"（定位/搜索/反查/初始值）时才允许被新落点的反查覆盖；用户手改过的名字保留
    private var nameIsAuto: Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == lastAutoName.trimmingCharacters(in: .whitespaces)
    }

    private var mergeHitName: String {
        mergeCandidate?.existingPlaceID
            .flatMap { id in existingPlaces.first { $0.id == id } }?.name ?? ""
    }

    private func restoreInitial() {
        guard let initial else { return }
        name = initial.name
        lastAutoName = initial.name
        if initial.latitude != 0 || initial.longitude != 0 {
            let coord = CLLocationCoordinate2D(latitude: initial.latitude, longitude: initial.longitude)
            pin = coord
            camera = .region(MKCoordinateRegion(center: coord,
                                                latitudinalMeters: 800, longitudinalMeters: 800))
        }
        categoryRaw = initial.categoryRaw
    }

    private func drop(at coord: CLLocationCoordinate2D, refillAutoName: Bool) {
        if let linked = linkedPlaceID,
           let place = existingPlaces.first(where: { $0.id == linked }),
           place.latitude != coord.latitude || place.longitude != coord.longitude {
            linkedPlaceID = nil
        }
        pin = coord
        camera = .region(MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 800, longitudinalMeters: 800))
        results = []
        guard refillAutoName, nameIsAuto else { return }
        Task {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                let suggested = [mark.name, mark.locality].compactMap { $0 }.joined(separator: " · ")
                // 反查是异步的：回来时若 pin 已移到别处、或用户已手输名字，这个结果就过期了，丢弃
                guard let current = pin,
                      current.latitude == coord.latitude, current.longitude == coord.longitude,
                      nameIsAuto else { return }
                name = suggested
                lastAutoName = suggested
            }
        }
    }

    private func select(_ item: MKMapItem) {
        if let n = item.name {
            name = n
            lastAutoName = n
        }
        drop(at: item.placemark.coordinate, refillAutoName: false)
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let visibleRegion {
            request.region = visibleRegion
        }
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            results = response?.mapItems ?? []
        }
    }

    private func locateMe() {
        locating = true
        Task {
            if let result = try? await LocationFetcher().fetch() {
                name = result.name
                lastAutoName = result.name
                drop(at: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude),
                     refillAutoName: false)
            }
            locating = false
        }
    }

    /// 点旧钉 = 直接关联既有地点：名字/坐标/分类全部沿用，不再新建（spec §七）
    private func adopt(_ place: CDPlace) {
        name = place.name ?? ""
        lastAutoName = name
        categoryRaw = place.categoryRaw
        linkedPlaceID = place.id
        drop(at: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
             refillAutoName: false)
    }
}
