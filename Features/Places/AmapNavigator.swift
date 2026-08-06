import UIKit
import MapKit

/// 跳高德导航（URL Scheme，免 Key 免注册）；未装高德自动退苹果地图路线。
/// 坐标系：App 内坐标来自苹果地图（国内即 GCJ-02），`dev=0` 告诉高德不再偏移，
/// 落点与 App 内地图看到的位置一致——这是国内地图跳转最容易踩的坑。
enum AmapNavigator {
    /// 高德路线选择页链接（驾车/步行/公交/骑行由用户在高德里挑）
    static func amapURL(name: String, latitude: Double, longitude: Double) -> URL? {
        var comps = URLComponents(string: "iosamap://path")
        comps?.queryItems = [
            URLQueryItem(name: "sourceApplication", value: "Anniversary"),
            URLQueryItem(name: "dlat", value: String(latitude)),
            URLQueryItem(name: "dlon", value: String(longitude)),
            URLQueryItem(name: "dname", value: name),
            URLQueryItem(name: "dev", value: "0"),
        ]
        return comps?.url
    }

    /// 装了高德跳高德路线页；没装退苹果地图路线（零配置，任何设备可用）
    @MainActor
    static func navigate(name: String, latitude: Double, longitude: Double) {
        if let url = amapURL(name: name, latitude: latitude, longitude: longitude),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: latitude, longitude: longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }
}
