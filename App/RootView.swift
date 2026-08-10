import SwiftUI

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
    @AppStorage("nameConfirmedCoupleID") private var confirmedCoupleID = ""

    var body: some View {
        Group {
            if let couple = couples.first {
                if JoinNameConfirm.isNeeded(
                    isParticipantDevice: CoupleRepository(context: context).isParticipantDevice(couple),
                    coupleID: couple.id,
                    confirmedCoupleID: confirmedCoupleID) {
                    JoinNameConfirmView(couple: couple)
                } else {
                    MainShell()
                }
            } else {
                OnboardingView()
            }
        }
        // 终审 F-1:accept 成功的 completion 回调里第一道 prune 会在真实时序里空转——
        // 那一刻共享 zone 记录还没镜像导入落地，本机只有私有 store 那 1 个 couple，
        // pruneEmptyLocalCouple 的 count>1 guard 直接 no-op；scenePhase 那道兜底又发生在
        // accept 之前，同样接不住"导入之后"这个时间点。这里补上共享库异步导入的触发点：
        // 镜像落地那一刻 couples.count 必然变化，借 FetchRequest 的这个信号再跑一遍 prune。
        // pruneEmptyLocalCouple 本身幂等（靠本机创建标记判据），多跑无副作用。
        .onChange(of: couples.count) { _, _ in
            try? CoupleRepository(context: context).pruneEmptyLocalCouple()
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PreviewData.makeController().viewContext)
}
