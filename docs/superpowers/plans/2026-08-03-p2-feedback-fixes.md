# P2 试用反馈补丁（编辑解锁 + 时间线白卡 + 地图选点）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落实用户真机试用的三条反馈：① 已存记忆的照片/地点/我的评价可修改；② 时间线一天内多条记忆改「白卡整包」分界（用户从三方案小样中选定 C）；③ 记忆地点从"仅一键定位"升级为"地图选点（搜索 + 落点 + 一键定位）"。

**Architecture:** 仓库层补三个编辑方法（addPhotos/deletePhoto/setPlace，TDD）；评价修改复用 P2 的 upsertEvaluation + EvaluationFormSheet（解锁按钮 + 预填）；新建 PlacePickerSheet（MapKit：MKLocalSearch 搜索、MapReader 点选落点、LocationFetcher 一键定位），创建与编辑共用；TimelineListView 换白卡呈现、MeetingDetailView 画布转米色。规范同步修订（时间线呈现规则 + 编辑能力 + 选点交互），50 米同名归并建议仍留 P3。

**Tech Stack:** SwiftUI + MapKit（iOS 17 Map API：MapCameraPosition/MapReader/Marker）+ Core Data。零第三方。

**基线：** main @ b081689（P2 已合并，61/61 测试绿）。分支 `worktree-p2-feedback-fixes`。

## Global Constraints（每个任务隐含遵守）

- 部署基线 iOS 18.0；纯 SwiftUI；零第三方依赖。
- 唯一交互色 actionBlue `#0066CC`；按钮文案单行 ≤6 字无 emoji（本计划新按钮全表：选地点 / 清除 / 定位 / 搜索 / 保存 / 取消 / 改我的评价——最后一个 5 字合规）。
- CDPlace 写入仍只允许 id/name/latitude/longitude/createdAt/couple 六字段；**categoryRaw 禁写**（P3 定枚举前）。
- 既有 `let _ = ….count` 观察行不得删改；写 authorPartnerID 一律经 `currentPartnerID(of:)`。
- 门禁：每任务收尾 `./scripts/test.sh` 须见 `✅ 测试通过`；涉 UI 任务另跑 `./scripts/build.sh` 须见 `✅ 构建通过`。测试用 `PersistenceController(inMemory: true)`，不依赖网络/定位。
- 提交信息中文，按步骤小步提交。

## 文件结构总览

```
docs/superpowers/specs/2026-07-29-anniversary-app-design.md  修订（T1）
Features/Meetings/TimelineListView.swift   白卡化（T1）
Features/Meetings/MeetingDetailView.swift  画布米色（T1）
Persistence/MomentRepository.swift         addPhotos/deletePhoto/setPlace（T2）
Tests/MomentRepositoryTests.swift          扩充（T2）
Features/Moments/MomentDetailView.swift    评价按钮常显（T3）
Features/Moments/EvaluationFormSheet.swift 预填（T3）
Features/Places/PlacePickerSheet.swift     新建（T4）
Features/Moments/MomentFormView.swift      编辑解锁 + 选点接入（T5）
project.yml                                CURRENT_PROJECT_VERSION 1→2（T6）
```

---

### Task 1: 规范修订 + 时间线白卡化

**Files:**
- Modify: `docs/superpowers/specs/2026-07-29-anniversary-app-design.md`
- Modify: `Features/Meetings/TimelineListView.swift`
- Modify: `Features/Meetings/MeetingDetailView.swift`

**Interfaces:**
- Consumes: `DS.canvas`/`DS.parchment`/`DS.hairline`（Color）/`DS.Radius.image`(8)/`DS.Radius.card`(12–14，以 DS.swift 实际值为准)。
- Produces: 时间线记忆卡的新视觉基准（后续任务与 P3 均以此为准）。

**背景：** 用户真机试用反馈"一天内各记忆分界不明显"，三方案小样对比后选定 **C · 白卡整包**：米色画布 + 每条记忆整体装进白色描边圆角卡、照片卡内内嵌（时间线不再全宽出血；**详情页保留出血+投影不动**）。

- [ ] **Step 1: 修订规范（三处）**

1. §6 ② 足迹「时间线」一段中，把「每条记忆 = **照片全宽出血（8px 圆角 + 全系统唯一投影）**+ 标题行…」改为：

> 每条记忆 = **白色描边圆角卡整包（米色画布上一眼一条；照片卡内内嵌 8px 圆角，无投影）**+ 标题行（类型/时刻小字）+ 两人短评直接露出（…原文其余不动…）

并在该行末尾追加：「（2026-08-03 真机试用修订：原"照片全宽出血"方案在多条记忆连排时分界不清，经三方案小样对比改为白卡整包；**详情页仍保留全宽出血+唯一投影**。）」

2. §7.4 组件对应表「记忆呈现（时间线/详情）」一行拆成两行：

| 记忆呈现（时间线） | 米色画布 + 白卡整包（hairline 描边、14 圆角、10pt 内距）；照片内嵌 8px 圆角无投影；评价行卡内直排 |
| 记忆呈现（详情页） | 照片全宽出血 8px 圆角 + 唯一投影；文字退到照片下方；评价块 parchment 圆角卡 |

3. §6「中央 ⊕ · 记忆」表单一段，把「地点（含归并建议）」改为「地点（**地图选点：搜索 / 地图落点 / 一键定位**；50 米同名归并建议 P3 实装）」；§6「记忆详情」的「编辑」改为「编辑（类型/标题/正文/时刻/**照片增删/地点/我的评价**均可改）」。

- [ ] **Step 2: TimelineListView 白卡化**

`momentCard(_:repo:)` 的返回视图整体改为（评价行等内部逻辑不动，只换容器与照片修饰）：

```swift
        return VStack(alignment: .leading, spacing: 6) {
            if let thumb, let ui = UIImage(data: thumb) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
            }
            // …标题行 HStack 与评价 VStack 原样保留…
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.hairline, lineWidth: 1))
```

要点：照片行删掉 `.dsPhotoShadow()`；原 `.padding(.bottom, 4)` 删除（卡间距交给 LazyVStack 的 spacing）。

- [ ] **Step 3: MeetingDetailView 画布转米色**

`grep -n "background(DS." Features/Meetings/MeetingDetailView.swift`，把最外层 `.background(DS.canvas)` 改为 `.background(DS.parchment)`（只改最外层画布；深色卡/白组卡等内部元素不动）。封盘晚安 DarkCard 与「第 n 天」日头无需改——深色卡与米色画布对比天然成立。

- [ ] **Step 4: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅（61 个，无新测试——视觉任务以构建 + 后续真机验收把关）。

- [ ] **Step 5: 提交**

```bash
git add docs/superpowers/specs/2026-07-29-anniversary-app-design.md Features/Meetings/TimelineListView.swift Features/Meetings/MeetingDetailView.swift
git commit -m "反馈②：时间线白卡整包分界（规范同步修订，详情页保留出血）"
```

---

### Task 2: MomentRepository 编辑能力（TDD）

**Files:**
- Modify: `Persistence/MomentRepository.swift`
- Test: `Tests/MomentRepositoryTests.swift`（追加进现有 class）

**Interfaces:**
- Consumes: `Thumbnailer.thumbnailData(from:)`、`photosSorted(_:)`（P1 既有）。
- Produces（T5 依赖的确切签名）:
  - `func addPhotos(_ moment: CDMoment, datas: [Data]) throws`（sortIndex 续接既有最大值）
  - `func deletePhoto(_ photo: CDPhoto) throws`
  - `func setPlace(_ moment: CDMoment, place: CDPlace?) throws`

- [ ] **Step 1: 写失败测试（追加）**

```swift
    func testAddPhotosAppendsAfterExistingSortIndex() throws {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let couple = try CoupleRepository(context: ctx)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let meetings = MeetingRepository(context: ctx)
        let meeting = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil)
        try meetings.start(meeting, at: Date())
        let repo = MomentRepository(context: ctx)
        let moment = try repo.create(in: meeting, type: .sight, title: "外滩", body: nil,
                                     happenedAt: Date(), photoDatas: [Data([1]), Data([2])],
                                     myEvaluation: nil, authorID: nil, place: nil)

        try repo.addPhotos(moment, datas: [Data([3])])
        let photos = repo.photosSorted(moment)
        XCTAssertEqual(photos.count, 3)
        XCTAssertEqual(photos.map(\.sortIndex), [0, 1, 2], "新增照片的 sortIndex 必须续接")
        XCTAssertEqual(photos.last?.imageData, Data([3]))

        try repo.deletePhoto(photos[1])
        XCTAssertEqual(repo.photosSorted(moment).count, 2)
        XCTAssertEqual(repo.photosSorted(moment).map(\.imageData), [Data([1]), Data([3])])
    }

    func testSetPlaceReplacesAndClears() throws {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let couple = try CoupleRepository(context: ctx)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let meetings = MeetingRepository(context: ctx)
        let meeting = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil)
        try meetings.start(meeting, at: Date())
        let repo = MomentRepository(context: ctx)
        let moment = try repo.create(in: meeting, type: .restaurant, title: "小馆", body: nil,
                                     happenedAt: Date(), photoDatas: [], myEvaluation: nil,
                                     authorID: nil, place: nil)

        let place = CDPlace(context: ctx)
        place.id = UUID(); place.name = "蟹家大院"; place.latitude = 31.2; place.longitude = 121.5
        place.createdAt = Date(); place.couple = couple

        try repo.setPlace(moment, place: place)
        XCTAssertEqual(moment.place?.name, "蟹家大院")
        try repo.setPlace(moment, place: nil)
        XCTAssertNil(moment.place)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`addPhotos` 等符号不存在（编译错误即失败形态）。

- [ ] **Step 3: 实现（追加在 move(_:to:) 之后）**

```swift
    /// 编辑模式追加照片：sortIndex 续接既有最大值，保持既有排序不变
    func addPhotos(_ moment: CDMoment, datas: [Data]) throws {
        let base = (photosSorted(moment).last?.sortIndex ?? -1) + 1
        for (i, data) in datas.enumerated() {
            let photo = CDPhoto(context: context)
            photo.id = UUID()
            photo.imageData = data
            photo.thumbnailData = Thumbnailer.thumbnailData(from: data)
            photo.sortIndex = base + Int32(i)
            photo.moment = moment
        }
        try context.save()
    }

    func deletePhoto(_ photo: CDPhoto) throws {
        context.delete(photo)
        try context.save()
    }

    /// 换/清地点。旧 CDPlace 不删（可能被其他记忆引用；地点档案与归并是 P3 范围）
    func setPlace(_ moment: CDMoment, place: CDPlace?) throws {
        moment.place = place
        try context.save()
    }
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（63 个）。

- [ ] **Step 5: 提交**

```bash
git add Persistence/MomentRepository.swift Tests/MomentRepositoryTests.swift
git commit -m "反馈①（仓库层）：照片增删与地点换清"
```

---

### Task 3: 我的评价可修改

**Files:**
- Modify: `Features/Moments/MomentDetailView.swift`
- Modify: `Features/Moments/EvaluationFormSheet.swift`

**Interfaces:**
- Consumes: `upsertEvaluation`（P2-T9，已含更新语义）、`evaluation(of:by:)`、`currentPartnerID(of:)`。
- Produces: 详情页评价卡在"已写"状态也有修改入口；表单打开时预填现值。

- [ ] **Step 0: MomentDetailView 补观察（P2 终局审查遗留，编辑落地后成刚需）**

`let moment: CDMoment` 改为 `@ObservedObject var moment: CDMoment`（NSManagedObject 天然 ObservableObject；不改则本补丁的照片增删/地点修改/评价修改保存后返回详情页不刷新）。调用方 `MomentDetailView(moment:)` 传参形式不变。

- [ ] **Step 1: MomentDetailView 按钮常显**

评价卡内我方分支现状是：有 myEval 显示星行+短评、无则「补上评价」按钮（P2-T9 改的）。改为**两种状态都有入口**——在 myEval 存在分支的短评之后追加：

```swift
                            Button("改我的评价") { showEvalForm = true }
                                .font(.system(size: 13))
                                .foregroundStyle(DS.actionBlue)
                                .buttonStyle(.plain)
```

（无 myEval 分支的「补上评价」GhostPill 按钮保持原样；`showEvalForm` 状态与 `.sheet` 挂接已存在，不动。）

- [ ] **Step 2: EvaluationFormSheet 预填**

加状态 `@State private var loaded = false`，在最外层 VStack 的修饰链上追加：

```swift
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let couples = CoupleRepository(context: context)
            if let couple = try? couples.fetchCouple(),
               let existing = MomentRepository(context: context)
                   .evaluation(of: moment, by: couples.currentPartnerID(of: couple)) {
                stars = Int(existing.stars)
                moodEmoji = existing.moodEmoji
                comment = existing.comment ?? ""
            }
        }
```

标题 `Text("补上我的评价")` 改为 `Text("我的评价")`（补/改两态共用）。

- [ ] **Step 3: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅（63 个；更新语义已被 T9 的 upsert 测试锁定，本任务纯 UI 解锁）。

- [ ] **Step 4: 提交**

```bash
git add Features/Moments/MomentDetailView.swift Features/Moments/EvaluationFormSheet.swift
git commit -m "反馈①（评价）：已写评价可修改，表单预填现值"
```

---

### Task 4: PlacePickerSheet 地图选点组件

**Files:**
- Create: `Features/Places/PlacePickerSheet.swift`

**Interfaces:**
- Consumes: `LocationFetcher().fetch() async throws -> (name: String, latitude: Double, longitude: Double)`（P1 既有）；DS 令牌与 `BluePillButtonStyle`。
- Produces（T5 依赖）:
  - `struct PickedPlace: Equatable { var name: String; var latitude: Double; var longitude: Double }`
  - `struct PlacePickerSheet: View { init(initial: PickedPlace?, onPick: @escaping (PickedPlace) -> Void) }`

**交互（spec §6 修订后）：** 搜索框 MKLocalSearch → 结果列表点选落点；地图任意点按落点（反查地名，仅在名字为空时自动填入）；「定位」按钮 = 一键当前位置；名称可手改；「保存」回传。UI + 网络不可单测，门禁 = 构建 + 既有测试绿。

- [ ] **Step 1: 新建文件（完整实现）**

```swift
import SwiftUI
import MapKit

struct PickedPlace: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// 记忆地点的地图选点：搜索 / 地图落点 / 一键定位 三合一。
/// 只回传 PickedPlace 值；CDPlace 的创建由调用方负责（保持六字段纪律）。
struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PickedPlace?
    let onPick: (PickedPlace) -> Void

    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var locating = false

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(name.isEmpty ? "所选地点" : name, coordinate: pin)
                            .tint(DS.actionBlue)
                    }
                }
                .onTapGesture { point in
                    guard let coord = proxy.convert(point, from: .local) else { return }
                    drop(at: coord, fillNameIfEmpty: true)
                }
            }
            .overlay(alignment: .top) { searchOverlay }
            .safeAreaInset(edge: .bottom) { confirmBar }
            .navigationTitle("选地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear { restoreInitial() }
        }
    }

    private var searchOverlay: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("搜索地点", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                Button("搜索") { runSearch() }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.actionBlue)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(DS.canvas))
            .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { i, item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "未命名").font(.system(size: 15)).foregroundStyle(DS.ink)
                                if let addr = item.placemark.title {
                                    Text(addr).font(.system(size: 11)).foregroundStyle(DS.inkMuted).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if i < min(results.count, 5) - 1 {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, DS.Spacing.md).padding(.top, 8)
    }

    private var confirmBar: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("地点名称", text: $name)
                    .textFieldStyle(.plain)
                Button(locating ? "定位中" : "定位") { locateMe() }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.actionBlue)
                    .disabled(locating)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.hairline, lineWidth: 1))

            Button("保存") {
                guard let pin else { return }
                onPick(PickedPlace(name: name.trimmingCharacters(in: .whitespaces),
                                   latitude: pin.latitude, longitude: pin.longitude))
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .disabled(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, DS.Spacing.md).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func restoreInitial() {
        guard let initial else { return }
        name = initial.name
        if initial.latitude != 0 || initial.longitude != 0 {
            let coord = CLLocationCoordinate2D(latitude: initial.latitude, longitude: initial.longitude)
            pin = coord
            camera = .region(MKCoordinateRegion(center: coord,
                                                latitudinalMeters: 800, longitudinalMeters: 800))
        }
    }

    private func drop(at coord: CLLocationCoordinate2D, fillNameIfEmpty: Bool) {
        pin = coord
        camera = .region(MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 800, longitudinalMeters: 800))
        results = []
        guard fillNameIfEmpty, name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                let suggested = [mark.name, mark.locality].compactMap { $0 }.joined(separator: " · ")
                if name.trimmingCharacters(in: .whitespaces).isEmpty { name = suggested }
            }
        }
    }

    private func select(_ item: MKMapItem) {
        name = item.name ?? name
        drop(at: item.placemark.coordinate, fillNameIfEmpty: false)
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            results = response?.mapItems ?? []
        }
    }

    private func locateMe() {
        locating = true
        Task {
            if let result = try? await LocationFetcher().fetch() {
                name = result.name
                drop(at: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude),
                     fillNameIfEmpty: false)
            }
            locating = false
        }
    }
}
```

- [ ] **Step 2: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅（63 个）。

- [ ] **Step 3: 提交**

```bash
git add Features/Places/PlacePickerSheet.swift
git commit -m "反馈③：地图选点组件（搜索/落点/一键定位三合一）"
```

---

### Task 5: MomentFormView 编辑解锁与选点接入

**Files:**
- Modify: `Features/Moments/MomentFormView.swift`

**Interfaces:**
- Consumes: `PickedPlace`/`PlacePickerSheet`（T4）、`addPhotos`/`deletePhoto`/`setPlace`（T2）、既有 create/update 管线。
- Produces: 创建与编辑两模式的完整表单能力（照片增删 / 地点选改清 / 评价入口维持 T3 的详情页路径）。

- [ ] **Step 1: 状态与模式扩展**

属性区追加：

```swift
    @State private var showPlacePicker = false
    @State private var existingPhotos: [CDPhoto] = []
    @State private var photosToDelete: [CDPhoto] = []
    @State private var loadedPlaceSignature = ""
```

计算属性追加：

```swift
    private var placeSignature: String {
        "\(locationName.trimmingCharacters(in: .whitespaces))|\(coords?.0 ?? 0)|\(coords?.1 ?? 0)"
    }
```

- [ ] **Step 2: body 分支解锁**

`VStack` 内容改为（去掉"暂不支持修改"提示行；编辑模式同样显示照片与地点区，评价区仍仅创建模式——编辑评价走详情页）：

```swift
                    typeChips
                    photoSection
                    fieldsSection
                    if !isEdit { evaluationSection }
                    locationSection
```

`.sheet(item: $staleDay)` 之后追加：

```swift
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerSheet(initial: coords.map {
                    PickedPlace(name: locationName, latitude: $0.0, longitude: $0.1)
                } ?? (locationName.isEmpty ? nil : PickedPlace(name: locationName, latitude: 0, longitude: 0))) { picked in
                    locationName = picked.name
                    coords = (picked.latitude, picked.longitude)
                }
            }
```

- [ ] **Step 3: photoSection 支持编辑模式**

`photoSection` 整体替换为（新增：编辑模式先列既有照片，✕ 标记待删；PhotosPicker 追加逻辑两模式共用）：

```swift
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                Text(photoDatas.isEmpty ? (isEdit ? "追加照片" : "选择照片") : "已选 \(photoDatas.count) 张")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.actionBlue)
            }
            if isEdit && !existingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(existingPhotos, id: \.objectID) { photo in
                            if let thumb = photo.thumbnailData, let ui = UIImage(data: thumb) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                    .opacity(photosToDelete.contains(photo) ? 0.3 : 1)
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            if let i = photosToDelete.firstIndex(of: photo) {
                                                photosToDelete.remove(at: i)
                                            } else {
                                                photosToDelete.append(photo)
                                            }
                                        } label: {
                                            Image(systemName: photosToDelete.contains(photo)
                                                  ? "arrow.uturn.backward.circle.fill" : "xmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(.white, DS.ink.opacity(0.55))
                                        }
                                        .padding(3)
                                    }
                            }
                        }
                    }
                }
                if !photosToDelete.isEmpty {
                    Text("已标记删除 \(photosToDelete.count) 张 · 保存后生效").dsFootnote()
                }
            }
            if !photoDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                            if let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }
```

- [ ] **Step 4: locationSection 接入选点**

`locationSection` 整体替换为（手输文字地点保留；「选地点」开地图；已有内容时给「清除」）：

```swift
    private var locationSection: some View {
        GroupedSection {
            HStack {
                Text("地点").dsBody()
                TextField("可手输或选点", text: $locationName).multilineTextAlignment(.trailing)
                if !locationName.isEmpty || coords != nil {
                    Button("清除") {
                        locationName = ""
                        coords = nil
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkMuted)
                }
                Button("选地点") { showPlacePicker = true }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.actionBlue)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
```

（原"定位"按钮功能已并入 PlacePickerSheet 的「定位」，此处不再重复。）

- [ ] **Step 5: loadIfEditing 与 save 编辑分支**

`loadIfEditing()` 末尾追加：

```swift
        existingPhotos = MomentRepository(context: context).photosSorted(moment)
        locationName = moment.place?.name ?? ""
        if let place = moment.place, place.latitude != 0 || place.longitude != 0 {
            coords = (place.latitude, place.longitude)
        }
        loadedPlaceSignature = placeSignature
```

`save()` 的 `.edit` 分支整体替换为：

```swift
        case let .edit(moment):
            let repo = MomentRepository(context: context)
            try? repo.update(moment, type: type, title: title,
                             body: bodyText.isEmpty ? nil : bodyText, happenedAt: happenedAt)
            for photo in photosToDelete { try? repo.deletePhoto(photo) }
            if !photoDatas.isEmpty { try? repo.addPhotos(moment, datas: photoDatas) }
            applyPlaceChangeIfNeeded(to: moment, repo: repo)
            dismiss()
```

同文件底部新增私有方法：

```swift
    /// 地点签名变了才动关系：清空→setPlace(nil)；有值→新建 CDPlace（六字段纪律）。
    /// 旧 CDPlace 不删（可能被其他记忆引用；归并与档案是 P3 范围）。
    private func applyPlaceChangeIfNeeded(to moment: CDMoment, repo: MomentRepository) {
        guard placeSignature != loadedPlaceSignature else { return }
        let trimmed = locationName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            try? repo.setPlace(moment, place: nil)
            return
        }
        let couples = CoupleRepository(context: context)
        guard let couple = try? couples.fetchCouple() else { return }
        let place = CDPlace(context: context)
        place.id = UUID()
        place.name = trimmed
        place.latitude = coords?.0 ?? 0
        place.longitude = coords?.1 ?? 0
        place.createdAt = Date()
        place.couple = couple
        try? repo.setPlace(moment, place: place)
    }
```

- [ ] **Step 6: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅（63 个）。

- [ ] **Step 7: 提交**

```bash
git add Features/Moments/MomentFormView.swift
git commit -m "反馈①③：编辑模式解锁照片增删与地点修改，创建/编辑统一走地图选点"
```

---

### Task 6: 构建号 2 + 终检

**Files:**
- Modify: `project.yml`（`CURRENT_PROJECT_VERSION: 1` → `2`）

**说明：** 修完这批要重新归档上传 TestFlight，构建号必须比上一个大，先在此垫好。

- [ ] **Step 1: 改版本号并重生成**

`project.yml` 里 `CURRENT_PROJECT_VERSION: 1` 改为 `CURRENT_PROJECT_VERSION: 2`。

Run: `./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`
Expected: 全部 ✅（63 个，最终门禁）。

- [ ] **Step 2: 提交**

```bash
git add project.yml
git commit -m "构建号 2：为反馈补丁的 TestFlight 重新上传垫底"
```

---

## 真机验收清单（合并后用户复测）

1. 旧记忆 → 编辑：追加 2 张照片、✕ 删 1 张旧照 → 保存 → 详情轮播反映增删。
2. 旧记忆 → 详情「改我的评价」→ 表单预填旧值 → 改星数保存 → 详情即时更新。
3. 旧记忆 → 编辑 → 「选地点」→ 地图搜索一家店 → 选中保存 → 详情地点更新。
4. 新建记忆 → 「选地点」→ 地图点按落点 → 名称自动反填 → 保存成功。
5. 新建记忆 → 「选地点」→ 「定位」→ 当前位置落点。
6. 时间线：同一天 3 条记忆（含 1 条无照片）→ 白卡分界一眼一条；封盘晚安卡样式不变；详情页照片仍出血带投影。
7. 地点清除：编辑旧记忆 → 「清除」→ 保存 → 详情不再显示地点行。
8. 选点手势冲突：已落钉后再点地图他处 → 钉子移动、已填名称不被覆盖；点按钉子本身后再点空白处，落点仍可继续更新（Map 与 Marker 手势不互吞）。
9. 她的设备（受邀方）回归：她编辑同一条旧记忆追加 1 张照片 + 「改我的评价」→ 同步后两端照片一致、评价各归各半、我的那半未被改动。
10. 时间线评价回显：从时间线进详情 → 改我的评价 → 返回时间线 → 该卡星数/短评**即时**更新（F1 修复的验证钩）。
11. 坐标提示语义：编辑带坐标旧记忆 → 表单出现「已带坐标 · 换店请重新选点」；只手输改店名不重选点 → 保存后详情显示新名而地图钉仍在原坐标（预期行为，提示已示警）。
12. 计划页画布：从首页倒计时卡与见面列表「计划中」卡两个入口进入计划页均为米色画布；见面详情内 时间线⇄计划 来回切换无画布跳变。

## 执行提示（SDD 控制器用）

- 模型：T2/T3/T6 转写型最低档；T1 中档（规范措辞 + 两文件 UI）；T4/T5 中档（MapKit 新组件 / 多状态接线）。任务审查中档；终局审查最高档。
- 测试计数：基线 61 → T2 后 63，此后不变。
- T4/T5 的 MapKit 交互（搜索/落点/定位）不可自动化验收，门禁到构建绿为止，端到端走上面的真机清单。
