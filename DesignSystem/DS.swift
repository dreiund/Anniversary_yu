import SwiftUI

func rgbComponents(hex: UInt32) -> (r: Double, g: Double, b: Double) {
    (
        r: Double((hex >> 16) & 0xFF) / 255.0,
        g: Double((hex >> 8) & 0xFF) / 255.0,
        b: Double(hex & 0xFF) / 255.0
    )
}

extension Color {
    init(hex: UInt32) {
        let c = rgbComponents(hex: hex)
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}

enum DS {
    // 画布
    static let canvas = Color(hex: 0xFFFFFF)
    static let parchment = Color(hex: 0xF5F5F7)
    static let darkCard = Color(hex: 0x272729)
    static let pureBlack = Color(hex: 0x000000)
    // 交互
    static let actionBlue = Color(hex: 0x0066CC)
    static let focusBlue = Color(hex: 0x0071E3)
    static let skyBlue = Color(hex: 0x2997FF)
    // 文字
    static let ink = Color(hex: 0x1D1D1F)
    static let inkMuted = Color(hex: 0x86868B)
    static let onDarkMuted = Color(hex: 0xCCCCCC)
    // 线与语义
    static let hairline = Color(hex: 0xE0E0E0)
    static let chipBorder = Color(hex: 0xD2D2D7)
    static let dsRed = Color(hex: 0xFF3B30)
    static let dsGreen = Color(hex: 0x34C759)
    static let roseCycle = Color(hex: 0xD96450)
    static let bandBlue = Color(hex: 0xEDF4FC)   // 日历见面带淡蓝（P3 spec §3.1）

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 17
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let image: CGFloat = 8
        static let card: CGFloat = 12
        static let darkCard: CGFloat = 14
        static let large: CGFloat = 18
    }
}

extension View {
    /// 全系统唯一投影，只用于落在页面上的照片（spec §7.2）
    func dsPhotoShadow() -> some View {
        shadow(color: .black.opacity(0.22), radius: 15, x: 3, y: 5)
    }
}
