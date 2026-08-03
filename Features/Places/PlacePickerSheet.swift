import SwiftUI
import MapKit

struct PickedPlace: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
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
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var locating = false

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(name.isEmpty ? "所选地点" : name, coordinate: pin)
                            .tint(DS.actionBlue)
                    }
                }
                .onTapGesture { point in
                    guard let coord = proxy.convert(point, from: .local) else { return }
                    drop(at: coord, fillNameIfEmpty: true)
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

            Button("保存") {
                guard let pin else { return }
                onPick(PickedPlace(name: name.trimmingCharacters(in: .whitespaces),
                                   latitude: pin.latitude, longitude: pin.longitude))
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .disabled(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, DS.Spacing.md).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func restoreInitial() {
        guard let initial else { return }
        name = initial.name
        if initial.latitude != 0 || initial.longitude != 0 {
            let coord = CLLocationCoordinate2D(latitude: initial.latitude, longitude: initial.longitude)
            pin = coord
            camera = .region(MKCoordinateRegion(center: coord,
                                                latitudinalMeters: 800, longitudinalMeters: 800))
        }
    }

    private func drop(at coord: CLLocationCoordinate2D, fillNameIfEmpty: Bool) {
        pin = coord
        camera = .region(MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 800, longitudinalMeters: 800))
        results = []
        guard fillNameIfEmpty, name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                let suggested = [mark.name, mark.locality].compactMap { $0 }.joined(separator: " · ")
                if name.trimmingCharacters(in: .whitespaces).isEmpty { name = suggested }
            }
        }
    }

    private func select(_ item: MKMapItem) {
        name = item.name ?? name
        drop(at: item.placemark.coordinate, fillNameIfEmpty: false)
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
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
                drop(at: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude),
                     fillNameIfEmpty: false)
            }
            locating = false
        }
    }
}
