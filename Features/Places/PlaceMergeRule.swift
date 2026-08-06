import Foundation
import CoreLocation

/// 50 米同店归并判定（spec §七）：距离 ≤50m 且名字相等/互为包含。不做拼音模糊匹配。
enum PlaceMergeRule {
    static func nameSimilar(_ a: String, _ b: String) -> Bool {
        let ta = a.trimmingCharacters(in: .whitespaces)
        let tb = b.trimmingCharacters(in: .whitespaces)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        return ta == tb || ta.contains(tb) || tb.contains(ta)
    }

    static func isCandidate(name: String, latitude: Double, longitude: Double,
                            existingName: String,
                            existingLatitude: Double, existingLongitude: Double) -> Bool {
        guard nameSimilar(name, existingName) else { return false }
        let d = CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: existingLatitude, longitude: existingLongitude))
        return d <= 50
    }
}
