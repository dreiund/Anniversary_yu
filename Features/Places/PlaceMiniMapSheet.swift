import SwiftUI
import MapKit
import CoreData

/// 临时小地图（反馈⑦抽出共用）：地点档案「在地图中查看」与行前日程点地点共用；
/// 只看位置不进地图页，关掉即走。
struct PlaceMiniMapSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let place: CDPlace

    var body: some View {
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
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if place.latitude != 0 || place.longitude != 0 {
                        Button("导航") { openInMapsNavigation(place: place) }
                    }
                }
            }
        }
    }
}
