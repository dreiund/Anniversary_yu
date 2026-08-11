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

    /// 反馈⑬①:深色适配——按外观动态取色(浅色值维持既有 hex 不变,只补暗色对应)
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            let c = rgbComponents(hex: hex)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }
}

enum DS {
    // 画布(反馈⑬①:全部 token 动态化——浅色值一律不变,暗色对应按系统灰阶+语义提亮)
    static let canvas = Color(light: 0xFFFFFF, dark: 0x2C2C2E)      // 卡面
    static let parchment = Color(light: 0xF5F5F7, dark: 0x1C1C1E)   // 页底
    static let darkCard = Color(light: 0x272729, dark: 0x3A3A3C)    // 墨卡:暗底下提亮一档保持可辨
    static let pureBlack = Color(hex: 0x000000)
    // 交互(暗色下按苹果惯例提亮,保证暗底对比)
    static let actionBlue = Color(light: 0x0066CC, dark: 0x409CFF)
    static let focusBlue = Color(light: 0x0071E3, dark: 0x409CFF)
    static let skyBlue = Color(light: 0x2997FF, dark: 0x64B5FF)
    // 文字
    static let ink = Color(light: 0x1D1D1F, dark: 0xF2F2F7)
    static let inkMuted = Color(light: 0x86868B, dark: 0x98989E)
    static let onDarkMuted = Color(hex: 0xCCCCCC)                   // 恒用于墨卡/照片上,不随外观
    // 线与语义
    static let hairline = Color(light: 0xE0E0E0, dark: 0x3A3A3C)
    static let chipBorder = Color(light: 0xD2D2D7, dark: 0x48484A)
    static let dsRed = Color(light: 0xFF3B30, dark: 0xFF453A)
    static let dsGreen = Color(light: 0x34C759, dark: 0x30D158)
    static let roseCycle = Color(light: 0xD96450, dark: 0xE0785F)
    static let dsOrange = Color(light: 0xFF9F0A, dark: 0xFFB340)   // 警示语义色：消极徽章 / 雷区描边（P4，不作行动色）
    static let bandBlue = Color(light: 0xEDF4FC, dark: 0x1E3248)   // 日历见面带淡蓝（P3 spec §3.1）
    static let rosePale = Color(light: 0xFDF1EF, dark: 0x3D2A28)   // 她页横幅/粉卡底（P5）
    static let roseCell = Color(light: 0xF8E3DF, dark: 0x4A2F2B)   // 经期天格浅粉底（P5，实红改浅红保四点可辨）
    static let ovulationBg = Color(light: 0xF0E6FA, dark: 0x35284A)   // 排卵期淡紫底（反馈⑥）
    static let ovulationInk = Color(light: 0x8E44AD, dark: 0xB983D9)  // 排卵期紫字（反馈⑥）

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
