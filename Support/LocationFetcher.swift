import CoreLocation

final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func fetch() async throws -> (name: String, latitude: Double, longitude: Double) {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        let location = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            continuation = cont
            manager.requestLocation()
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = [placemark?.name, placemark?.locality]
            .compactMap { $0 }
            .joined(separator: " · ")
        return (name.isEmpty ? "已记录坐标" : name,
                location.coordinate.latitude, location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first {
            continuation?.resume(returning: loc)
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
