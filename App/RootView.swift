import SwiftUI

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
    @AppStorage("nameConfirmedCoupleID") private var confirmedCoupleID = ""

    var body: some View {
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
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PreviewData.makeController().viewContext)
}
