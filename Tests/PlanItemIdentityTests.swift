import XCTest
@testable import Anniversary

final class PlanItemIdentityTests: XCTestCase {
    func testPlanItemIdentifiableWitnessIsBusinessUUID() throws {
        let pc = PersistenceController(inMemory: true)
        let item = CDPlanItem(context: pc.viewContext)
        let uuid = UUID()
        item.id = uuid
        func identity<T: Identifiable>(_ value: T) -> T.ID { value.id }
        // 若 Identifiable 见证退化为 ObjectIdentifier，下一行编译失败（类型不符），
        // 即锁定：跨上下文/跨设备的 ForEach 身份 = 业务 UUID，不是类实例地址。
        let resolved: UUID? = identity(item)
        XCTAssertEqual(resolved, uuid)
    }
}
