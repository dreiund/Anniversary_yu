import Foundation

enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }

    static let ymd = make("yyyy年M月d日")   // 反馈⑭:全 App 日期中文化(原 yyyy.MM.dd 西式点分)
    static let monthDay = make("M月d日")
    static let monthDayWeek = make("M月d日 EEE")
    static let hm = make("HH:mm")
}
