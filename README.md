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
