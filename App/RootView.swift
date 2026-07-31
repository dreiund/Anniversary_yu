import SwiftUI

struct RootView: View {
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>

    var body: some View {
        if couples.isEmpty {
            OnboardingView()
        } else {
            MainShell()
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PreviewData.makeController().viewContext)
}
