import SwiftUI
import CoreData

/// 圆角照片钉（spec §4.1）。无照片：米灰底 + 名首字墨字。
struct PlacePin: View {
    let image: UIImage?
    let fallbackText: String
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    DS.parchment
                    Text(String(fallbackText.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(DS.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
        .overlay(RoundedRectangle(cornerRadius: size * 0.3).stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

extension CDPlace {
    /// 该地点最新记忆的首图缩略（钉与档案头共用）
    func latestThumbnail(context: NSManagedObjectContext) -> UIImage? {
        let repo = MomentRepository(context: context)
        let sorted = ((moments as? Set<CDMoment>) ?? [])
            .sorted { ($0.happenedAt ?? .distantPast) > ($1.happenedAt ?? .distantPast) }
        for moment in sorted {
            if let data = repo.photosSorted(moment).first?.thumbnailData,
               let img = UIImage(data: data) {
                return img
            }
        }
        return nil
    }
}
