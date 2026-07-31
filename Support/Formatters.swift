import Foundation

enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }

    static let ymd = make("yyyy.MM.dd")
    static let monthDay = make("M月d日")
    static let monthDayWeek = make("M月d日 EEE")
    static let hm = make("HH:mm")
}
