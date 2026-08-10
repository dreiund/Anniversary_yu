import CloudKit
import CoreData

/// P6-T4:accept 失败不再只 print——广播出去，由在场的容器（MainShell／引导页）接住弹提示。
extension Notification.Name {
    static let shareAcceptFailed = Notification.Name("shareAcceptFailed")
}

/// 情侣空间唯一一次配对的全部 CKShare 操作。
/// 策略：链接即可加入（publicPermission .readWrite），链接只经微信私发；
/// 对方加入后由「锁定邀请」把 publicPermission 关为 .none——门先开、人进来、再锁门。
@MainActor
final class SharingManager: ObservableObject {
    /// nonisolated：不可变字符串常量，不依赖任何隔离状态，configure 从 nonisolated 上下文读取它。
    nonisolated static let shareTitle = "我们的纪念空间"

    private let controller: PersistenceController
    @Published private(set) var share: CKShare?
    @Published private(set) var lastError: String?

    init(controller: PersistenceController) {
        self.controller = controller
    }

    var participantJoined: Bool { Self.participantJoined(in: share) }

    /// 除 owner 外存在已接受的参与者
    /// nonisolated：只读参数里的 share，不碰任何 @MainActor 隔离状态，
    /// 单测需要在非 MainActor 的同步上下文里直接调用（见编译修复说明）。
    nonisolated static func participantJoined(in share: CKShare?) -> Bool {
        guard let share else { return false }
        return share.participants.contains { $0.role != .owner && $0.acceptanceStatus == .accepted }
    }

    /// nonisolated：同上，只改参数里的 share 本身，不涉及实例状态。
    nonisolated static func configure(_ share: CKShare) {
        share[CKShare.SystemFieldKey.title] = shareTitle
        share.publicPermission = .readWrite
    }

    func loadShare(for couple: CDCouple) async {
        do {
            let shares = try controller.container.fetchShares(matching: [couple.objectID])
            share = shares[couple.objectID]
        } catch {
            lastError = "读取配对状态失败"
        }
    }

    /// 已有 share 直接返回；没有则创建（couple 整树迁入共享 zone）、配置并持久化。
    func ensureShare(for couple: CDCouple) async throws -> CKShare {
        if let existing = try share ?? controller.container.fetchShares(matching: [couple.objectID])[couple.objectID] {
            // 上次建 share 后 persist 失败的遗留、或解绑后遗留：无参与者却是 .none → 补一次配置（同链接复活）。
            // （正常锁定后的 share 同为 .none 但已有参与者，不能重开。）
            if existing.publicPermission == .none, !Self.participantJoined(in: existing),
               let store = controller.privateStore {
                Self.configure(existing)
                let persisted = try await controller.container.persistUpdatedShare(existing, in: store)
                share = persisted
                return persisted
            }
            share = existing
            return existing
        }
        let (_, newShare, _) = try await controller.container.share([couple], to: nil)
        Self.configure(newShare)
        if let store = controller.privateStore {
            let persisted = try await controller.container.persistUpdatedShare(newShare, in: store)
            share = persisted
            return persisted
        }
        share = newShare
        return newShare
    }

    /// 她加入后关门：新人无法再经链接加入，既有参与者不受影响。
    func lockInvites() async {
        lastError = nil
        guard let share, let store = controller.privateStore else { return }
        let original = share.publicPermission
        share.publicPermission = .none
        do {
            self.share = try await controller.container.persistUpdatedShare(share, in: store)
        } catch {
            share.publicPermission = original  // 回滚：云端未锁成，本地不得谎报已锁
            lastError = "锁定失败，请重试"
        }
    }

    /// 受邀方 delegate 入口（T7）。接受后镜像自动把共享 zone 导入共享库，
    /// RootView 的 couple FetchRequest 随之非空，界面自动进入主壳。
    /// P6-B1:接受成功后顺带自愈——如果本机之前等不及邀请就自己建了空单人空间，
    /// 私有 store 里那份空壳残留现在已是纯冗余，趁此刻清掉（App 前台激活是第二道保险）。
    /// completion 不保证在主线程回调，Core Data 访问经 context.perform 切回 context 自己的队列。
    nonisolated static func accept(_ metadata: CKShare.Metadata) {
        let controller = PersistenceController.shared
        guard let sharedStore = controller.sharedStore else { return }
        controller.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                print("接受邀请失败：\(error)")
                // completion 不保证在主线程回调，NotificationCenter 的 UI 订阅方需要主线程投递。
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .shareAcceptFailed, object: nil)
                }
                return
            }
            let context = controller.viewContext
            context.perform {
                try? CoupleRepository(context: context).pruneEmptyLocalCouple()
            }
        }
    }
}

/// 设置页配对区的展示状态（spec §一 规则表）
enum PairingStatus: Equatable {
    case notPaired, invited, connected

    var label: String {
        switch self {
        case .notPaired: return "未配对"
        case .invited: return "邀请已发出"
        case .connected: return "已连接"
        }
    }
}

extension SharingManager {
    /// nonisolated 纯函数：只依赖入参，单测直调。
    /// 解绑后遗留的"已锁且无参与者" share 视同未配对——生成邀请走既有重开分支同链接复活。
    nonisolated static func pairingStatus(shareExists: Bool, participantJoined: Bool,
                                          publicPermissionOpen: Bool,
                                          isParticipantDevice: Bool) -> PairingStatus {
        if isParticipantDevice { return .connected }
        guard shareExists else { return .notPaired }
        if participantJoined { return .connected }
        return publicPermissionOpen ? .invited : .notPaired
    }

    /// 创建方解除配对：移除全部非 owner 参与者并锁链接，一次持久化。
    /// 失败时参与者移除无法本地回滚（CKShare 不支持重加），重拉云端真相代替回滚。
    func unpair(for couple: CDCouple) async {
        lastError = nil
        guard let share, let store = controller.privateStore else { return }
        share.participants.filter { $0.role != .owner }.forEach(share.removeParticipant)
        share.publicPermission = .none
        do {
            self.share = try await controller.container.persistUpdatedShare(share, in: store)
        } catch {
            await loadShare(for: couple)
            lastError = "解除失败，请重试"
        }
    }

    /// 受邀方解除配对：清除共享 zone（CloudKit 定义的"参与者退出共享"）。
    /// 成功后本机共享库清空 → RootView 的 couple FetchRequest 变空 → 自动回引导页。
    func leaveSpace(for couple: CDCouple) async {
        lastError = nil
        guard let sharedStore = controller.sharedStore,
              let zoneID = controller.container.recordID(for: couple.objectID)?.zoneID else {
            lastError = "解除失败，请重试"
            return
        }
        do {
            _ = try await controller.container.purgeObjectsAndRecordsInZone(with: zoneID, in: sharedStore)
        } catch {
            lastError = "解除失败，请重试"
        }
    }
}
