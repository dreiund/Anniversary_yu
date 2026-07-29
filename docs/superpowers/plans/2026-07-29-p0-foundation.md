# P0 地基 实现计划（计划 1/7）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可构建、可测试的 iOS 工程地基：XcodeGen 工程骨架 + Apple 摄影优先风设计系统组件库（含画廊页）+ 全部 15 个 Core Data 实体的程序化模型 + 本地持久化栈 + 情侣空间引导仓库，全部通过单元测试。

**Architecture:** 纯 SwiftUI 单工程，XcodeGen 生成 xcodeproj（工程文件不入库）；Core Data 模型用**程序化 NSManagedObjectModel**（无 .xcdatamodeld，纯代码可 diff 可测试）；持久化用 NSPersistentCloudKitContainer 但 P0 阶段 `cloudKitContainerOptions = nil`（不开同步，P2 打开时零迁移）；从第一天遵守 CloudKit 建模约束并用测试锁死。

**Tech Stack:** Swift 5.10 / SwiftUI / Core Data (NSPersistentCloudKitContainer) / XCTest / XcodeGen（仅开发工具，非运行时依赖）

**范围说明:** 设计文档 `docs/superpowers/specs/2026-07-29-anniversary-app-design.md` 的 P0 阶段。P1–P6 各自单独成计划，本计划完成后再写 P1。SwiftData 共享能力已于 2026-07-29 查证（仍不支持 CKShare），维持 Core Data 方案，无需再议。

## Global Constraints

- 部署目标 **iOS 18.0**；仅 iPhone（TARGETED_DEVICE_FAMILY=1）；竖屏。
- **零第三方运行时依赖**；开发工具仅允许 XcodeGen（brew 安装）。
- Bundle ID：`com.fkc.anniversary`；显示名暂用 `Anniversary`（待定，见 spec 开放项 1）。
- **CloudKit 建模约束**（P0 起强制，测试锁死）：所有关系 optional；非 optional 属性必须有 defaultValue；不用 unique constraint；不用 ordered relationship（用 `sortIndex` 排序）；业务主键是 `id: UUID` 属性。
- 照片/证据图二进制属性开启 `allowsExternalBinaryDataStorage`（原图不压缩，spec §3.3）。
- 视觉令牌以 spec §7.1/§7.2 为准（行动蓝 `#0066CC`、墨色 `#1D1D1F`、米色 `#F5F5F7`、深卡 `#272729`、经期玫瑰 `#D96450` 等）；深色内容一律圆角卡片不做通栏；按钮文案单行 ≤6 字无 emoji。
- 全部 UI 文案简体中文；代码注释仅在表达代码本身说不清的约束时才写。
- 每个任务以 `./scripts/test.sh`（或 build.sh）通过 + git commit 收尾；commit 信息用中文、动词开头。
- 工程生成物不入库：`.gitignore` 已含 `Anniversary.xcodeproj/`、`.build/`（Task 1 添加）。

---

### Task 1: 工具链与可构建工程骨架

**Files:**
- Create: `project.yml`
- Create: `App/AnniversaryApp.swift`
- Create: `App/RootView.swift`
- Create: `scripts/gen.sh`、`scripts/build.sh`、`scripts/test.sh`、`scripts/run.sh`
- Create: `Tests/SmokeTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: 无（起点）
- Produces: 可构建工程；四个脚本（后续所有任务只用 `./scripts/test.sh` 跑测试、`./scripts/gen.sh` 在新增文件后重新生成工程）；`RootView`（Task 5 会改它）

- [ ] **Step 1: 确认工具链**

Run: `xcodebuild -version && (command -v xcodegen || brew install xcodegen)`
Expected: 打印 Xcode 版本；xcodegen 可用（首次可能触发 brew 安装）。

- [ ] **Step 2: 写 project.yml**

```yaml
name: Anniversary
options:
  createIntermediateGroups: true
  deploymentTarget:
    iOS: "18.0"
settings:
  base:
    SWIFT_VERSION: "5.10"
    GENERATE_INFOPLIST_FILE: YES
    CURRENT_PROJECT_VERSION: 1
    MARKETING_VERSION: 0.1.0
targets:
  Anniversary:
    type: application
    platform: iOS
    sources:
      - App
      - DesignSystem
      - Domain
      - Persistence
      - Support
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fkc.anniversary
        INFOPLIST_KEY_CFBundleDisplayName: Anniversary
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
        TARGETED_DEVICE_FAMILY: "1"
    scheme:
      testTargets:
        - AnniversaryTests
  AnniversaryTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests
    dependencies:
      - target: Anniversary
```

注意：`sources` 引用的五个目录本任务就要全部存在，否则 xcodegen 报错——`DesignSystem`、`Domain`、`Persistence`、`Support` 先各放一个空的 `.gitkeep`。

Run: `mkdir -p App DesignSystem Domain Persistence Support Tests scripts && touch DesignSystem/.gitkeep Domain/.gitkeep Persistence/.gitkeep Support/.gitkeep`

- [ ] **Step 3: 写 App 入口与占位 RootView**

`App/AnniversaryApp.swift`:
```swift
import SwiftUI

@main
struct AnniversaryApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Anniversary · P0")
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 4: 写四个脚本并加执行权限**

`scripts/gen.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "缺少 xcodegen: brew install xcodegen"; exit 1; }
xcodegen generate
```

`scripts/build.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*$//')
[ -n "$SIM" ] || { echo "未找到可用 iPhone 模拟器"; exit 1; }
echo "▶ 模拟器: $SIM"
xcodebuild build \
  -project Anniversary.xcodeproj -scheme Anniversary \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath .build -quiet
echo "✅ 构建通过"
```

`scripts/test.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*$//')
[ -n "$SIM" ] || { echo "未找到可用 iPhone 模拟器"; exit 1; }
echo "▶ 模拟器: $SIM"
xcodebuild test \
  -project Anniversary.xcodeproj -scheme Anniversary \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath .build -quiet
echo "✅ 测试通过"
```

`scripts/run.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
SIM=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*$//')
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted ".build/Build/Products/Debug-iphonesimulator/Anniversary.app"
xcrun simctl launch booted com.fkc.anniversary
```

Run: `chmod +x scripts/*.sh`

- [ ] **Step 5: 写冒烟测试**

`Tests/SmokeTests.swift`:
```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testTargetLinks() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: 生成工程并跑测试**

Run: `printf 'Anniversary.xcodeproj/\n.build/\n' >> .gitignore && ./scripts/gen.sh && ./scripts/test.sh`
Expected: `✅ 测试通过`

- [ ] **Step 7: Commit**

```bash
git add project.yml App scripts Tests .gitignore DesignSystem Domain Persistence Support
git commit -m "搭建 XcodeGen 工程骨架与构建测试脚本"
```

---

### Task 2: 设计令牌 DS（色彩 / 间距 / 圆角 / 阴影 / 排版）

**Files:**
- Create: `DesignSystem/DS.swift`
- Create: `DesignSystem/DSTypography.swift`
- Test: `Tests/DSTokenTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `DS`（静态令牌：`DS.canvas/.parchment/.darkCard/.actionBlue/.focusBlue/.skyBlue/.ink/.inkMuted/.onDarkMuted/.hairline/.dsRed/.dsGreen/.roseCycle`，`DS.Spacing.xxs...xxl`，`DS.Radius.image/.card/.darkCard/.large`，`rgbComponents(hex:)`）；文字样式修饰符 `.dsHero() .dsPageTitle() .dsSectionTitle() .dsBody() .dsCaption() .dsFootnote()`；照片投影 `.dsPhotoShadow()`

- [ ] **Step 1: 写失败测试（hex 解析）**

`Tests/DSTokenTests.swift`:
```swift
import XCTest
@testable import Anniversary

final class DSTokenTests: XCTestCase {
    func testRGBComponentsParsesHex() {
        let c = rgbComponents(hex: 0xF5F5F7)
        XCTAssertEqual(c.r, 245.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.g, 245.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.b, 247.0 / 255.0, accuracy: 0.0001)
    }

    func testActionBlueComponents() {
        let c = rgbComponents(hex: 0x0066CC)
        XCTAssertEqual(c.r, 0, accuracy: 0.0001)
        XCTAssertEqual(c.g, 102.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.b, 204.0 / 255.0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（`rgbComponents` 未定义，编译错误即视为失败）

- [ ] **Step 3: 写 DS.swift**

```swift
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
```

- [ ] **Step 4: 写 DSTypography.swift**

```swift
import SwiftUI

extension View {
    /// 首页大字（在一起 N 天）：SF 紧排
    func dsHero() -> some View {
        font(.system(size: 34, weight: .semibold)).tracking(-0.8).foregroundStyle(DS.ink)
    }

    /// 页面大标题（第 1 天 / 上海 · 8.29–9.02）
    func dsPageTitle() -> some View {
        font(.system(size: 22, weight: .semibold)).tracking(-0.4).foregroundStyle(DS.ink)
    }

    /// 区块标题（提醒 / 备忘 / 8月29日 周五）
    func dsSectionTitle() -> some View {
        font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
    }

    /// 正文 17pt（Apple 的阅读节奏）
    func dsBody() -> some View {
        font(.system(size: 17)).foregroundStyle(DS.ink)
    }

    func dsCaption() -> some View {
        font(.system(size: 14)).foregroundStyle(DS.inkMuted)
    }

    func dsFootnote() -> some View {
        font(.system(size: 12)).foregroundStyle(DS.inkMuted)
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add DesignSystem Tests/DSTokenTests.swift
git commit -m "添加设计令牌与排版样式（Apple 摄影优先风 §7）"
```

---

### Task 3: 按钮组件族

**Files:**
- Create: `DesignSystem/DSButtons.swift`

**Interfaces:**
- Consumes: `DS` 令牌（Task 2）
- Produces: `BluePillButtonStyle`、`GhostPillButtonStyle`、`DarkUtilityButtonStyle`、`DSPressEffect`（全部 `ButtonStyle`；用法 `Button("封盘"){}.buttonStyle(BluePillButtonStyle())`）

- [ ] **Step 1: 写 DSButtons.swift**

```swift
import SwiftUI

/// 全系统按压微交互 scale(0.95)（spec §7.2）
struct DSPressEffect: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 主按钮：行动蓝实心药丸
struct BluePillButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(DS.actionBlue))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 次按钮：蓝描边幽灵药丸
struct GhostPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(DS.actionBlue)
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .background(Capsule().stroke(DS.actionBlue, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 工具按钮：墨色小圆角矩形
struct DarkUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 15)
            .background(RoundedRectangle(cornerRadius: 8).fill(DS.ink))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 16) {
        Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
        Button("封盘") {}.buttonStyle(BluePillButtonStyle(fullWidth: true))
        Button("接受 TA 的邀请") {}.buttonStyle(GhostPillButtonStyle())
        Button("编辑") {}.buttonStyle(DarkUtilityButtonStyle())
    }
    .padding()
    .background(DS.canvas)
}
```

- [ ] **Step 2: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh`
Expected: `✅ 构建通过`

- [ ] **Step 3: Commit**

```bash
git add DesignSystem/DSButtons.swift
git commit -m "添加按钮组件族（蓝药丸/幽灵/墨色工具钮）"
```

---

### Task 4: 卡片、分组列表、chip 与毛玻璃栏

**Files:**
- Create: `DesignSystem/DSCards.swift`
- Create: `DesignSystem/DSChips.swift`

**Interfaces:**
- Consumes: `DS` 令牌
- Produces: `DarkCard{}`、`ParchmentCard{}`、`GroupedSection{}`、`GroupedRow(title:value:showsDivider:)`、`FrostedBottomBar{}`、`SelectableChip(title:isSelected:action:)`

- [ ] **Step 1: 写 DSCards.swift**

```swift
import SwiftUI

/// 深色内容卡：一律圆角卡片留边距，禁止通栏（spec §7.2 用户修正①）
struct DarkCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.darkCard))
    }
}

struct ParchmentCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.parchment))
    }
}

/// iOS 分组列表容器（白组卡 + hairline 描边）
struct GroupedSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.canvas)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))
    }
}

struct GroupedRow: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = DS.inkMuted
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 15)).foregroundStyle(DS.ink)
                Spacer()
                if let value {
                    Text(value).font(.system(size: 14)).foregroundStyle(valueColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if showsDivider {
                DS.hairline.frame(height: 1).padding(.leading, 14)
            }
        }
    }
}

/// 底部毛玻璃栏（Tab 栏 / 计划页统计栏）
struct FrostedBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { DS.hairline.frame(height: 1) }
    }
}

#Preview {
    VStack(spacing: 16) {
        DarkCard {
            VStack(spacing: 4) {
                Text("距下次见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                Text("12 天").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                Text("查看行前计划 · 已安排 5 项 ›").font(.system(size: 13)).foregroundStyle(DS.skyBlue)
            }
        }
        ParchmentCard { Text("今日心情").dsCaption() }
        GroupedSection {
            GroupedRow(title: "配对状态", value: "已连接 ✓", valueColor: DS.dsGreen)
            GroupedRow(title: "在一起的日子", value: "2025.06.09 ›")
            GroupedRow(title: "Face ID 锁", value: "开", valueColor: DS.actionBlue, showsDivider: false)
        }
        FrostedBottomBar {
            HStack {
                Text("已安排 5 项 · 完成 2 项").dsCaption()
                Spacer()
                Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
            }
        }
    }
    .padding()
    .background(DS.parchment)
}
```

- [ ] **Step 2: 写 DSChips.swift**

```swift
import SwiftUI

/// 分段/筛选 chip：选中态 = focusBlue 描边 + 蓝字（spec §7.4）
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DS.actionBlue : DS.ink)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(DS.canvas))
                .overlay(
                    Capsule().stroke(
                        isSelected ? DS.focusBlue : DS.chipBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(DSPressEffect())
    }
}

#Preview {
    HStack {
        SelectableChip(title: "时间线", isSelected: true)
        SelectableChip(title: "路线", isSelected: false)
        SelectableChip(title: "计划", isSelected: false)
    }
    .padding()
    .background(DS.parchment)
}
```

- [ ] **Step 3: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh`
Expected: `✅ 构建通过`

- [ ] **Step 4: Commit**

```bash
git add DesignSystem/DSCards.swift DesignSystem/DSChips.swift
git commit -m "添加卡片/分组列表/chip/毛玻璃栏组件"
```

---

### Task 5: 组件画廊页并接入 RootView

**Files:**
- Create: `DesignSystem/DSGallery.swift`
- Modify: `App/RootView.swift`

**Interfaces:**
- Consumes: Task 2–4 全部组件
- Produces: `DSGallery`（P0 期间 app 的可见界面；P1 换成真首页时移到调试入口）

- [ ] **Step 1: 写 DSGallery.swift**

```swift
import SwiftUI

struct DSGallery: View {
    private let colors: [(String, Color)] = [
        ("canvas", DS.canvas), ("parchment", DS.parchment), ("darkCard", DS.darkCard),
        ("actionBlue", DS.actionBlue), ("focusBlue", DS.focusBlue), ("skyBlue", DS.skyBlue),
        ("ink", DS.ink), ("inkMuted", DS.inkMuted), ("hairline", DS.hairline),
        ("dsRed", DS.dsRed), ("dsGreen", DS.dsGreen), ("roseCycle", DS.roseCycle),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text("设计系统画廊").dsHero()

                Text("色彩").dsSectionTitle()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 8) {
                    ForEach(colors, id: \.0) { name, color in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: DS.Radius.image)
                                .fill(color)
                                .frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.image).stroke(DS.hairline, lineWidth: 1))
                            Text(name).dsFootnote()
                        }
                    }
                }

                Text("排版").dsSectionTitle()
                VStack(alignment: .leading, spacing: 6) {
                    Text("在一起 412 天").dsHero()
                    Text("第 1 天 · 页面标题").dsPageTitle()
                    Text("区块标题").dsSectionTitle()
                    Text("正文 17pt：排了四十分钟的队，但是值得。").dsBody()
                    Text("说明文字 14pt").dsCaption()
                    Text("脚注 12pt").dsFootnote()
                }

                Text("按钮").dsSectionTitle()
                VStack(spacing: 10) {
                    Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
                    Button("封盘") {}.buttonStyle(BluePillButtonStyle(fullWidth: true))
                    Button("接受 TA 的邀请") {}.buttonStyle(GhostPillButtonStyle())
                    Button("编辑") {}.buttonStyle(DarkUtilityButtonStyle())
                }

                Text("chip 分段").dsSectionTitle()
                HStack {
                    SelectableChip(title: "时间线", isSelected: true)
                    SelectableChip(title: "路线", isSelected: false)
                    SelectableChip(title: "计划", isSelected: false)
                }

                Text("卡片").dsSectionTitle()
                DarkCard {
                    VStack(spacing: 4) {
                        Text("距下次见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                        Text("12 天").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                        Text("查看行前计划 · 已安排 5 项 ›").font(.system(size: 13)).foregroundStyle(DS.skyBlue)
                    }
                }
                ParchmentCard {
                    HStack {
                        Text("今日心情").dsCaption()
                        Spacer()
                        Text("她还没打卡").dsFootnote()
                    }
                }
                GroupedSection {
                    GroupedRow(title: "她记了「外滩夜景」", value: "补上你的评价 ›", valueColor: DS.actionBlue)
                    GroupedRow(title: "经期第 2 天", value: "多关心她 ›")
                    GroupedRow(title: "昨天忘了封盘？", value: "一键补封 ›", valueColor: DS.actionBlue, showsDivider: false)
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .safeAreaInset(edge: .bottom) {
            FrostedBottomBar {
                HStack {
                    Text("已安排 5 项 · 完成 2 项").dsCaption()
                    Spacer()
                    Button("添加日程") {}.buttonStyle(BluePillButtonStyle())
                }
            }
        }
    }
}

#Preview {
    DSGallery()
}
```

- [ ] **Step 2: RootView 改为显示画廊**

`App/RootView.swift` 全文替换：
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        DSGallery()
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 3: 构建并在模拟器里人工过目**

Run: `./scripts/gen.sh && ./scripts/run.sh`
Expected: 模拟器启动 app，画廊页可滚动：色板 12 色、排版六级、四种按钮、chip、深卡/米卡/分组列表、底部毛玻璃栏。对照 spec §7 检查色值与形态无误。

- [ ] **Step 4: Commit**

```bash
git add DesignSystem/DSGallery.swift App/RootView.swift
git commit -m "添加设计系统画廊页作为 P0 可见界面"
```

---

### Task 6: 领域枚举（持久化 raw 值锁死）

**Files:**
- Create: `Domain/DomainEnums.swift`
- Test: `Tests/DomainEnumTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `MeetingStatus`、`MomentType`、`LedgerCategory`、`EntryVisibility`、`FlowLevel`、`PainLevel`、`CycleColor`（全部 `Int16` raw，带中文 `title`；raw 值即数据库存储值，永不改动）

- [ ] **Step 1: 写失败测试**

`Tests/DomainEnumTests.swift`:
```swift
import XCTest
@testable import Anniversary

final class DomainEnumTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(MeetingStatus.planned.rawValue, 0)
        XCTAssertEqual(MeetingStatus.ongoing.rawValue, 1)
        XCTAssertEqual(MeetingStatus.finished.rawValue, 2)

        XCTAssertEqual(MomentType.restaurant.rawValue, 0)
        XCTAssertEqual(MomentType.sight.rawValue, 1)
        XCTAssertEqual(MomentType.activity.rawValue, 2)
        XCTAssertEqual(MomentType.stay.rawValue, 3)
        XCTAssertEqual(MomentType.other.rawValue, 4)

        XCTAssertEqual(LedgerCategory.praise.rawValue, 0)
        XCTAssertEqual(LedgerCategory.complaint.rawValue, 1)
        XCTAssertEqual(LedgerCategory.like.rawValue, 2)
        XCTAssertEqual(LedgerCategory.trigger.rawValue, 3)

        XCTAssertEqual(EntryVisibility.sharedImmediately.rawValue, 0)
        XCTAssertEqual(EntryVisibility.privateUntilRevealed.rawValue, 1)

        XCTAssertEqual(FlowLevel.veryHeavy.rawValue, 4)
        XCTAssertEqual(PainLevel.severe.rawValue, 3)
        XCTAssertEqual(CycleColor.other.rawValue, 4)
    }

    func testChineseTitles() {
        XCTAssertEqual(MomentType.restaurant.title, "餐厅")
        XCTAssertEqual(LedgerCategory.trigger.title, "雷区")
        XCTAssertEqual(FlowLevel.medium.title, "中")
        XCTAssertEqual(PainLevel.mild.title, "轻")
        XCTAssertEqual(CycleColor.brightRed.title, "鲜红")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（类型未定义）

- [ ] **Step 3: 写 DomainEnums.swift**

```swift
import Foundation

// raw 值会写入数据库并跨设备同步：只许追加，禁止修改或删除已有 case。

enum MeetingStatus: Int16 {
    case planned = 0, ongoing = 1, finished = 2
}

enum MomentType: Int16, CaseIterable {
    case restaurant = 0, sight = 1, activity = 2, stay = 3, other = 4

    var title: String {
        switch self {
        case .restaurant: "餐厅"
        case .sight: "景点"
        case .activity: "活动"
        case .stay: "住宿"
        case .other: "其他"
        }
    }
}

enum LedgerCategory: Int16, CaseIterable {
    case praise = 0, complaint = 1, like = 2, trigger = 3

    var title: String {
        switch self {
        case .praise: "积极"
        case .complaint: "消极"
        case .like: "喜欢"
        case .trigger: "雷区"
        }
    }
}

enum EntryVisibility: Int16 {
    case sharedImmediately = 0, privateUntilRevealed = 1
}

enum FlowLevel: Int16, CaseIterable {
    case none = 0, light = 1, medium = 2, heavy = 3, veryHeavy = 4

    var title: String {
        switch self {
        case .none: "无"
        case .light: "少"
        case .medium: "中"
        case .heavy: "多"
        case .veryHeavy: "极多"
        }
    }
}

enum PainLevel: Int16, CaseIterable {
    case none = 0, mild = 1, moderate = 2, severe = 3

    var title: String {
        switch self {
        case .none: "无"
        case .mild: "轻"
        case .moderate: "中"
        case .severe: "重"
        }
    }
}

enum CycleColor: Int16, CaseIterable {
    case brightRed = 0, darkRed = 1, brown = 2, pink = 3, other = 4

    var title: String {
        switch self {
        case .brightRed: "鲜红"
        case .darkRed: "暗红"
        case .brown: "褐色"
        case .pink: "粉"
        case .other: "其他"
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Domain/DomainEnums.swift Tests/DomainEnumTests.swift
git commit -m "添加领域枚举并用测试锁死持久化 raw 值"
```

---

### Task 7: 托管对象与程序化 Core Data 模型（P0 最大任务）

**Files:**
- Create: `Domain/ManagedObjects.swift`
- Create: `Domain/ModelSchema.swift`
- Test: `Tests/ModelSchemaTests.swift`

**Interfaces:**
- Consumes: 无（枚举 raw 由调用方转换）
- Produces: `ModelSchema.model: NSManagedObjectModel`（进程内单例，供容器使用）；15 个 `NSManagedObject` 子类 `CDCouple/CDPartner/CDMeeting/CDDateDay/CDMoment/CDPhoto/CDEvaluation/CDPlace/CDDailyMood/CDLedgerEntry/CDEvidence/CDCycle/CDCycleDayLog/CDIntimacyRecord/CDPlanItem`（属性名见下方代码，后续所有任务以此为准）

- [ ] **Step 1: 写失败测试**

`Tests/ModelSchemaTests.swift`:
```swift
import XCTest
import CoreData
@testable import Anniversary

final class ModelSchemaTests: XCTestCase {
    let model = ModelSchema.model

    func testAllEntitiesPresent() {
        let names = Set(model.entities.compactMap(\.name))
        let expected: Set<String> = [
            "CDCouple", "CDPartner", "CDMeeting", "CDDateDay", "CDMoment",
            "CDPhoto", "CDEvaluation", "CDPlace", "CDDailyMood", "CDLedgerEntry",
            "CDEvidence", "CDCycle", "CDCycleDayLog", "CDIntimacyRecord", "CDPlanItem",
        ]
        XCTAssertEqual(names, expected)
    }

    func testCloudKitConstraint_AllRelationshipsOptional() {
        for entity in model.entities {
            for (name, rel) in entity.relationshipsByName {
                XCTAssertTrue(rel.isOptional, "\(entity.name ?? "?").\(name) 必须 optional（CloudKit 约束）")
            }
        }
    }

    func testCloudKitConstraint_NonOptionalAttributesHaveDefaults() {
        for entity in model.entities {
            for (name, attr) in entity.attributesByName where !attr.isOptional {
                XCTAssertNotNil(attr.defaultValue, "\(entity.name ?? "?").\(name) 非 optional 必须有默认值（CloudKit 约束）")
            }
        }
    }

    func testCloudKitConstraint_NoUniqueConstraints_NoOrderedRelationships() {
        for entity in model.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") 不得有 unique constraint")
            for (name, rel) in entity.relationshipsByName {
                XCTAssertFalse(rel.isOrdered, "\(entity.name ?? "?").\(name) 不得是 ordered relationship")
            }
        }
    }

    func testAllRelationshipsHaveInverses() {
        for entity in model.entities {
            for (name, rel) in entity.relationshipsByName {
                XCTAssertNotNil(rel.inverseRelationship, "\(entity.name ?? "?").\(name) 缺少 inverse")
            }
        }
    }

    func testImageBlobsUseExternalStorage() {
        let photo = model.entitiesByName["CDPhoto"]!
        let evidence = model.entitiesByName["CDEvidence"]!
        let partner = model.entitiesByName["CDPartner"]!
        XCTAssertTrue(photo.attributesByName["imageData"]!.allowsExternalBinaryDataStorage)
        XCTAssertTrue(evidence.attributesByName["imageData"]!.allowsExternalBinaryDataStorage)
        XCTAssertTrue(partner.attributesByName["avatarData"]!.allowsExternalBinaryDataStorage)
    }

    func testObjectGraphSaveAndFetchRoundTrip() throws {
        let container = NSPersistentContainer(name: "RoundTrip", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        let ctx = container.viewContext

        let couple = CDCouple(context: ctx)
        couple.id = UUID()
        couple.createdAt = Date()

        let meeting = CDMeeting(context: ctx)
        meeting.id = UUID()
        meeting.index = 7
        meeting.city = "上海"
        meeting.statusRaw = MeetingStatus.ongoing.rawValue
        meeting.couple = couple

        let day = CDDateDay(context: ctx)
        day.id = UUID()
        day.dayIndex = 1
        day.openedAt = Date()
        day.meeting = meeting

        let moment = CDMoment(context: ctx)
        moment.id = UUID()
        moment.title = "蟹家大院"
        moment.typeRaw = MomentType.restaurant.rawValue
        moment.happenedAt = Date()
        moment.dateDay = day

        let eval = CDEvaluation(context: ctx)
        eval.id = UUID()
        eval.stars = 5
        eval.moodEmoji = "😋"
        eval.comment = "秃黄油拌饭封神"
        eval.moment = moment

        let plan = CDPlanItem(context: ctx)
        plan.id = UUID()
        plan.title = "G102 高铁"
        plan.isDone = true
        plan.meeting = meeting

        try ctx.save()

        let fetched = try ctx.fetch(CDMoment.fetchRequest()) as! [CDMoment]
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.dateDay?.meeting?.city, "上海")
        XCTAssertEqual((fetched.first?.evaluations as? Set<CDEvaluation>)?.count, 1)
        let plans = try ctx.fetch(CDPlanItem.fetchRequest()) as! [CDPlanItem]
        XCTAssertEqual(plans.first?.meeting?.id, meeting.id)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（类型未定义）

- [ ] **Step 3: 写 ManagedObjects.swift**

```swift
import CoreData

// 命名约定：authorPartnerID 是 CDPartner.id 的非关系引用（避免向 Partner 挂十几个 inverse；查询经 CoupleRepository）。
// to-many 统一为 NSSet?，读取时 `as? Set<CDX>` 后按 sortIndex / 时间排序。

@objc(CDCouple)
final class CDCouple: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var anniversaryDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var partners: NSSet?
    @NSManaged var meetings: NSSet?
    @NSManaged var places: NSSet?
    @NSManaged var dailyMoods: NSSet?
    @NSManaged var ledgerEntries: NSSet?
    @NSManaged var cycles: NSSet?
    @NSManaged var intimacyRecords: NSSet?
}

@objc(CDPartner)
final class CDPartner: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var avatarData: Data?
    @NSManaged var themeColorHex: String?
    @NSManaged var cloudUserID: String?
    @NSManaged var tracksCycle: Bool
    @NSManaged var couple: CDCouple?
}

@objc(CDMeeting)
final class CDMeeting: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var index: Int32
    @NSManaged var title: String?
    @NSManaged var city: String?
    @NSManaged var plannedStart: Date?
    @NSManaged var plannedEnd: Date?
    @NSManaged var startedAt: Date?
    @NSManaged var endedAt: Date?
    @NSManaged var statusRaw: Int16
    @NSManaged var coverPhotoID: UUID?
    @NSManaged var couple: CDCouple?
    @NSManaged var dateDays: NSSet?
    @NSManaged var planItems: NSSet?
}

@objc(CDDateDay)
final class CDDateDay: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var dayIndex: Int32
    @NSManaged var openedAt: Date?
    @NSManaged var closedAt: Date?
    @NSManaged var meeting: CDMeeting?
    @NSManaged var moments: NSSet?
    @NSManaged var intimacyRecords: NSSet?
}

@objc(CDMoment)
final class CDMoment: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var typeRaw: Int16
    @NSManaged var title: String?
    @NSManaged var body: String?
    @NSManaged var happenedAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var dateDay: CDDateDay?
    @NSManaged var place: CDPlace?
    @NSManaged var photos: NSSet?
    @NSManaged var evaluations: NSSet?
}

@objc(CDPhoto)
final class CDPhoto: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var caption: String?
    @NSManaged var sortIndex: Int32
    @NSManaged var moment: CDMoment?
}

@objc(CDEvaluation)
final class CDEvaluation: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var stars: Int16
    @NSManaged var moodEmoji: String?
    @NSManaged var comment: String?
    @NSManaged var moment: CDMoment?
}

@objc(CDPlace)
final class CDPlace: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var address: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var categoryRaw: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var moments: NSSet?
    @NSManaged var ledgerEntries: NSSet?
    @NSManaged var planItems: NSSet?
}

@objc(CDDailyMood)
final class CDDailyMood: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var day: Date?
    @NSManaged var moodEmoji: String?
    @NSManaged var note: String?
    @NSManaged var couple: CDCouple?
}

@objc(CDLedgerEntry)
final class CDLedgerEntry: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var categoryRaw: Int16
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var title: String?
    @NSManaged var detail: String?
    @NSManaged var happenedAt: Date?
    @NSManaged var visibilityRaw: Int16
    @NSManaged var revealedAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var place: CDPlace?
    @NSManaged var evidences: NSSet?
}

@objc(CDEvidence)
final class CDEvidence: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var sortIndex: Int32
    @NSManaged var ledgerEntry: CDLedgerEntry?
}

@objc(CDCycle)
final class CDCycle: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var predictedStartAtLogging: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var dayLogs: NSSet?
}

@objc(CDCycleDayLog)
final class CDCycleDayLog: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var day: Date?
    @NSManaged var flowRaw: Int16
    @NSManaged var painRaw: Int16
    @NSManaged var colorRaw: Int16
    @NSManaged var note: String?
    @NSManaged var cycle: CDCycle?
}

@objc(CDIntimacyRecord)
final class CDIntimacyRecord: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var happenedAt: Date?
    @NSManaged var protectionUsed: NSNumber?
    @NSManaged var note: String?
    @NSManaged var couple: CDCouple?
    @NSManaged var dateDay: CDDateDay?
}

@objc(CDPlanItem)
final class CDPlanItem: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var day: Date?
    @NSManaged var time: Date?
    @NSManaged var title: String?
    @NSManaged var note: String?
    @NSManaged var isDone: Bool
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var sortIndex: Int32
    @NSManaged var placeText: String?
    @NSManaged var meeting: CDMeeting?
    @NSManaged var place: CDPlace?
}
```

- [ ] **Step 4: 写 ModelSchema.swift**

```swift
import CoreData

enum ModelSchema {
    /// 进程内唯一模型实例（两个容器共用同一 model，避免重复实体注册警告）
    static let model: NSManagedObjectModel = makeModel()

    private static func makeModel() -> NSManagedObjectModel {
        // 属性
        func attr(
            _ name: String, _ type: NSAttributeType,
            optional: Bool = true, defaultValue: Any? = nil, external: Bool = false
        ) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = defaultValue
            a.allowsExternalBinaryDataStorage = external
            return a
        }

        func entity(_ name: String, _ cls: AnyClass, _ attrs: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(cls)
            e.properties = attrs
            return e
        }

        // 一对多 + 逆关系；cascade=true 表示删父删子
        func oneToMany(
            _ parent: NSEntityDescription, _ toMany: String,
            _ child: NSEntityDescription, _ toOne: String,
            cascade: Bool = true
        ) {
            let many = NSRelationshipDescription()
            many.name = toMany
            many.destinationEntity = child
            many.minCount = 0
            many.maxCount = 0
            many.isOptional = true
            many.deleteRule = cascade ? .cascadeDeleteRule : .nullifyDeleteRule

            let one = NSRelationshipDescription()
            one.name = toOne
            one.destinationEntity = parent
            one.minCount = 0
            one.maxCount = 1
            one.isOptional = true
            one.deleteRule = .nullifyDeleteRule

            many.inverseRelationship = one
            one.inverseRelationship = many
            parent.properties.append(many)
            child.properties.append(one)
        }

        let couple = entity("CDCouple", CDCouple.self, [
            attr("id", .UUIDAttributeType),
            attr("anniversaryDate", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        let partner = entity("CDPartner", CDPartner.self, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("avatarData", .binaryDataAttributeType, external: true),
            attr("themeColorHex", .stringAttributeType),
            attr("cloudUserID", .stringAttributeType),
            attr("tracksCycle", .booleanAttributeType, optional: false, defaultValue: false),
        ])

        let meeting = entity("CDMeeting", CDMeeting.self, [
            attr("id", .UUIDAttributeType),
            attr("index", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("title", .stringAttributeType),
            attr("city", .stringAttributeType),
            attr("plannedStart", .dateAttributeType),
            attr("plannedEnd", .dateAttributeType),
            attr("startedAt", .dateAttributeType),
            attr("endedAt", .dateAttributeType),
            attr("statusRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("coverPhotoID", .UUIDAttributeType),
        ])

        let dateDay = entity("CDDateDay", CDDateDay.self, [
            attr("id", .UUIDAttributeType),
            attr("dayIndex", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("openedAt", .dateAttributeType),
            attr("closedAt", .dateAttributeType),
        ])

        let moment = entity("CDMoment", CDMoment.self, [
            attr("id", .UUIDAttributeType),
            attr("typeRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("title", .stringAttributeType),
            attr("body", .stringAttributeType),
            attr("happenedAt", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
        ])

        let photo = entity("CDPhoto", CDPhoto.self, [
            attr("id", .UUIDAttributeType),
            attr("imageData", .binaryDataAttributeType, external: true),
            attr("thumbnailData", .binaryDataAttributeType),
            attr("caption", .stringAttributeType),
            attr("sortIndex", .integer32AttributeType, optional: false, defaultValue: 0),
        ])

        let evaluation = entity("CDEvaluation", CDEvaluation.self, [
            attr("id", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("stars", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("moodEmoji", .stringAttributeType),
            attr("comment", .stringAttributeType),
        ])

        let place = entity("CDPlace", CDPlace.self, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("address", .stringAttributeType),
            attr("latitude", .doubleAttributeType, optional: false, defaultValue: 0.0),
            attr("longitude", .doubleAttributeType, optional: false, defaultValue: 0.0),
            attr("categoryRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("createdAt", .dateAttributeType),
        ])

        let dailyMood = entity("CDDailyMood", CDDailyMood.self, [
            attr("id", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("day", .dateAttributeType),
            attr("moodEmoji", .stringAttributeType),
            attr("note", .stringAttributeType),
        ])

        let ledger = entity("CDLedgerEntry", CDLedgerEntry.self, [
            attr("id", .UUIDAttributeType),
            attr("categoryRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("detail", .stringAttributeType),
            attr("happenedAt", .dateAttributeType),
            attr("visibilityRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("revealedAt", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        let evidence = entity("CDEvidence", CDEvidence.self, [
            attr("id", .UUIDAttributeType),
            attr("imageData", .binaryDataAttributeType, external: true),
            attr("thumbnailData", .binaryDataAttributeType),
            attr("sortIndex", .integer32AttributeType, optional: false, defaultValue: 0),
        ])

        let cycle = entity("CDCycle", CDCycle.self, [
            attr("id", .UUIDAttributeType),
            attr("startDate", .dateAttributeType),
            attr("endDate", .dateAttributeType),
            attr("predictedStartAtLogging", .dateAttributeType),
        ])

        let cycleLog = entity("CDCycleDayLog", CDCycleDayLog.self, [
            attr("id", .UUIDAttributeType),
            attr("day", .dateAttributeType),
            attr("flowRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("painRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("colorRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("note", .stringAttributeType),
        ])

        let intimacy = entity("CDIntimacyRecord", CDIntimacyRecord.self, [
            attr("id", .UUIDAttributeType),
            attr("happenedAt", .dateAttributeType),
            attr("protectionUsed", .booleanAttributeType),
            attr("note", .stringAttributeType),
        ])

        let planItem = entity("CDPlanItem", CDPlanItem.self, [
            attr("id", .UUIDAttributeType),
            attr("day", .dateAttributeType),
            attr("time", .dateAttributeType),
            attr("title", .stringAttributeType),
            attr("note", .stringAttributeType),
            attr("isDone", .booleanAttributeType, optional: false, defaultValue: false),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("sortIndex", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("placeText", .stringAttributeType),
        ])

        // 关系（父 → 子）
        oneToMany(couple, "partners", partner, "couple")
        oneToMany(couple, "meetings", meeting, "couple")
        oneToMany(couple, "places", place, "couple")
        oneToMany(couple, "dailyMoods", dailyMood, "couple")
        oneToMany(couple, "ledgerEntries", ledger, "couple")
        oneToMany(couple, "cycles", cycle, "couple")
        oneToMany(couple, "intimacyRecords", intimacy, "couple")
        oneToMany(meeting, "dateDays", dateDay, "meeting")
        oneToMany(meeting, "planItems", planItem, "meeting")
        oneToMany(dateDay, "moments", moment, "dateDay")
        oneToMany(dateDay, "intimacyRecords", intimacy, "dateDay", cascade: false)
        oneToMany(moment, "photos", photo, "moment")
        oneToMany(moment, "evaluations", evaluation, "moment")
        oneToMany(place, "moments", moment, "place", cascade: false)
        oneToMany(place, "ledgerEntries", ledger, "place", cascade: false)
        oneToMany(place, "planItems", planItem, "place", cascade: false)
        oneToMany(ledger, "evidences", evidence, "ledgerEntry")
        oneToMany(cycle, "dayLogs", cycleLog, "cycle")

        let model = NSManagedObjectModel()
        model.entities = [
            couple, partner, meeting, dateDay, moment, photo, evaluation, place,
            dailyMood, ledger, evidence, cycle, cycleLog, intimacy, planItem,
        ]
        return model
    }
}
```

- [ ] **Step 5: 跑测试确认全部通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS（含 7 个 schema 测试）

- [ ] **Step 6: Commit**

```bash
git add Domain/ManagedObjects.swift Domain/ModelSchema.swift Tests/ModelSchemaTests.swift
git commit -m "添加程序化 Core Data 模型与 15 个实体（CloudKit 约束测试锁死）"
```

---

### Task 8: 持久化控制器

**Files:**
- Create: `Persistence/PersistenceController.swift`
- Modify: `App/AnniversaryApp.swift`
- Test: `Tests/PersistenceControllerTests.swift`

**Interfaces:**
- Consumes: `ModelSchema.model`（Task 7）
- Produces: `PersistenceController(inMemory: Bool = false)`、`PersistenceController.shared`、`.container: NSPersistentCloudKitContainer`、`.viewContext`；App 已注入 `\.managedObjectContext`

- [ ] **Step 1: 写失败测试**

`Tests/PersistenceControllerTests.swift`:
```swift
import XCTest
import CoreData
@testable import Anniversary

final class PersistenceControllerTests: XCTestCase {
    func testInMemoryStackLoadsAndSaves() throws {
        let pc = PersistenceController(inMemory: true)
        XCTAssertEqual(pc.container.persistentStoreCoordinator.persistentStores.count, 1)

        let ctx = pc.viewContext
        let couple = CDCouple(context: ctx)
        couple.id = UUID()
        couple.createdAt = Date()
        try ctx.save()

        let fetched = try ctx.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(fetched.count, 1)
    }

    func testMergePolicyIsPropertyObjectTrump() {
        let pc = PersistenceController(inMemory: true)
        XCTAssertTrue((pc.viewContext.mergePolicy as? NSMergePolicy) === NSMergePolicy.mergeByPropertyObjectTrump)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（`PersistenceController` 未定义）

- [ ] **Step 3: 写 PersistenceController.swift**

```swift
import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Anniversary", managedObjectModel: ModelSchema.model)

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: dir.appendingPathComponent("Anniversary.sqlite"))
        }
        // P0 不开云同步；P2 在此设置 cloudKitContainerOptions 与共享库描述
        description.cloudKitContainerOptions = nil
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        precondition(loadError == nil, "本地库加载失败: \(String(describing: loadError))")

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
}
```

- [ ] **Step 4: App 注入托管上下文**

`App/AnniversaryApp.swift` 全文替换：
```swift
import SwiftUI

@main
struct AnniversaryApp: App {
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Persistence/PersistenceController.swift App/AnniversaryApp.swift Tests/PersistenceControllerTests.swift
git commit -m "添加持久化控制器（云同步关闭待 P2 开启）并注入 App"
```

---

### Task 9: 情侣空间引导仓库

**Files:**
- Create: `Persistence/CoupleRepository.swift`
- Test: `Tests/CoupleRepositoryTests.swift`

**Interfaces:**
- Consumes: `PersistenceController`、`CDCouple/CDPartner`
- Produces: `CoupleRepository(context:)`，方法 `bootstrapIfNeeded(myName:partnerName:anniversary:) throws -> CDCouple`、`fetchCouple() throws -> CDCouple?`、`partners(of:) -> [CDPartner]`（按创建先后：`[0]`=创建者/我，`[1]`=对方）

- [ ] **Step 1: 写失败测试**

`Tests/CoupleRepositoryTests.swift`:
```swift
import XCTest
@testable import Anniversary

final class CoupleRepositoryTests: XCTestCase {
    func testBootstrapCreatesCoupleWithTwoPartners() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)
        let anniversary = Date(timeIntervalSince1970: 1_749_398_400)

        let couple = try repo.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: anniversary)

        XCTAssertNotNil(couple.id)
        XCTAssertEqual(couple.anniversaryDate, anniversary)
        let partners = repo.partners(of: couple)
        XCTAssertEqual(partners.count, 2)
        XCTAssertEqual(partners[0].name, "阿铖")
        XCTAssertEqual(partners[1].name, "小于")
    }

    func testBootstrapIsIdempotent() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)

        let first = try repo.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let second = try repo.bootstrapIfNeeded(myName: "别人", partnerName: "别人2", anniversary: Date())

        XCTAssertEqual(first.objectID, second.objectID)
        let all = try pc.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(repo.partners(of: second).map(\.name), ["阿铖", "小于"])
    }

    func testFetchCoupleReturnsNilBeforeBootstrap() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)
        XCTAssertNil(try repo.fetchCouple())
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（`CoupleRepository` 未定义）

- [ ] **Step 3: 写 CoupleRepository.swift**

```swift
import CoreData

struct CoupleRepository {
    let context: NSManagedObjectContext

    func fetchCouple() throws -> CDCouple? {
        let request = CDCouple.fetchRequest()
        request.fetchLimit = 1
        return try context.fetch(request).first as? CDCouple
    }

    @discardableResult
    func bootstrapIfNeeded(myName: String, partnerName: String, anniversary: Date?) throws -> CDCouple {
        if let existing = try fetchCouple() { return existing }

        let now = Date()
        let couple = CDCouple(context: context)
        couple.id = UUID()
        couple.createdAt = now
        couple.anniversaryDate = anniversary

        // 集合无序，roleIndex 持久化"谁是创建者"：0=创建者/我，1=对方
        let me = CDPartner(context: context)
        me.id = UUID()
        me.name = myName
        me.themeColorHex = "0"
        me.couple = couple

        let partner = CDPartner(context: context)
        partner.id = UUID()
        partner.name = partnerName
        partner.themeColorHex = "1"
        partner.couple = couple

        try context.save()
        return couple
    }

    /// [0]=创建者/我，[1]=对方（bootstrap 用 themeColorHex 暂存 "0"/"1" 作稳定序，
    /// P1 引入正式主题色时改为独立 roleIndex 属性）
    func partners(of couple: CDCouple) -> [CDPartner] {
        let set = (couple.partners as? Set<CDPartner>) ?? []
        return set.sorted { ($0.themeColorHex ?? "") < ($1.themeColorHex ?? "") }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS（三个用例全绿）

- [ ] **Step 5: Commit**

```bash
git add Persistence/CoupleRepository.swift Tests/CoupleRepositoryTests.swift
git commit -m "添加情侣空间引导仓库（幂等 bootstrap 与双伙伴查询）"
```

---

### Task 10: 预览样例数据、收尾与 P0 验收

**Files:**
- Create: `Support/PreviewData.swift`
- Create: `README.md`
- Delete: `DesignSystem/.gitkeep`、`Domain/.gitkeep`、`Persistence/.gitkeep`、`Support/.gitkeep`

**Interfaces:**
- Consumes: 全部前序产物
- Produces: `PreviewData.controller`（含样例情侣与一次见面的内存栈，P1 起所有 SwiftUI Preview 用它）；README（构建/测试说明）

- [ ] **Step 1: 写 PreviewData.swift**

```swift
import CoreData

enum PreviewData {
    /// 预览与手动调试用内存栈：一对情侣 + 一次进行中的见面 + 一条已封盘的约会日
    static func makeController() -> PersistenceController {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let repo = CoupleRepository(context: ctx)

        do {
            let couple = try repo.bootstrapIfNeeded(
                myName: "阿铖", partnerName: "小于",
                anniversary: Calendar.current.date(byAdding: .day, value: -412, to: Date())
            )

            let meeting = CDMeeting(context: ctx)
            meeting.id = UUID()
            meeting.index = 7
            meeting.city = "上海"
            meeting.statusRaw = MeetingStatus.ongoing.rawValue
            meeting.startedAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            meeting.couple = couple

            let day1 = CDDateDay(context: ctx)
            day1.id = UUID()
            day1.dayIndex = 1
            day1.openedAt = meeting.startedAt
            day1.closedAt = Calendar.current.date(byAdding: .hour, value: 12, to: meeting.startedAt!)
            day1.meeting = meeting

            let moment = CDMoment(context: ctx)
            moment.id = UUID()
            moment.title = "蟹家大院"
            moment.typeRaw = MomentType.restaurant.rawValue
            moment.happenedAt = day1.openedAt
            moment.createdAt = day1.openedAt
            moment.dateDay = day1

            let eval = CDEvaluation(context: ctx)
            eval.id = UUID()
            eval.authorPartnerID = repo.partners(of: couple)[0].id
            eval.stars = 5
            eval.moodEmoji = "😋"
            eval.comment = "秃黄油拌饭封神"
            eval.moment = moment

            let plan = CDPlanItem(context: ctx)
            plan.id = UUID()
            plan.title = "G102 高铁"
            plan.isDone = true
            plan.sortIndex = 0
            plan.meeting = meeting

            try ctx.save()
        } catch {
            assertionFailure("PreviewData 构建失败: \(error)")
        }
        return pc
    }
}
```

- [ ] **Step 2: 写 README.md**

```markdown
# Anniversary

私人情侣周年纪念 iOS App（双人 iCloud 共享）。设计文档：`docs/superpowers/specs/2026-07-29-anniversary-app-design.md`。

## 开发

- 依赖：Xcode（iOS 18 SDK）、XcodeGen（`brew install xcodegen`）
- 生成工程：`./scripts/gen.sh`（新增/删除源文件后需重跑）
- 构建：`./scripts/build.sh` · 测试：`./scripts/test.sh` · 模拟器运行：`./scripts/run.sh`
- 工程文件不入库；Core Data 模型是程序化代码（`Domain/ModelSchema.swift`），无 .xcdatamodeld

## 阶段

P0 地基（本仓库当前状态）→ P1 记忆核心 → P2 双人同步 → P3 视图 → P4 小本本 → P5 她 → P6 打磨。
各阶段实现计划在 `docs/superpowers/plans/`。
```

- [ ] **Step 3: 清理占位文件并全量回归**

Run: `rm -f DesignSystem/.gitkeep Domain/.gitkeep Persistence/.gitkeep Support/.gitkeep && ./scripts/gen.sh && ./scripts/test.sh && ./scripts/run.sh`
Expected: 测试全绿；模拟器画廊正常显示。

- [ ] **Step 4: Commit（P0 完成）**

```bash
git add -A
git commit -m "添加预览样例数据与 README，P0 地基完成"
```

---

## P0 验收清单

- `./scripts/test.sh` 全绿（冒烟 + 令牌 + 枚举 + 模型 7 项 CloudKit 约束 + 持久化 + 仓库，共 ≥15 个用例）
- `./scripts/run.sh` 打开画廊页，色彩/排版/按钮/卡片/chip/毛玻璃栏与 spec §7 一致
- `git log` 呈现 10 次小步提交
- 无第三方运行时依赖；`Anniversary.xcodeproj` 与 `.build/` 不在版本库中
