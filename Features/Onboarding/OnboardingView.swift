import SwiftUI

struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()

    private var canCreate: Bool {
        !myName.trimmingCharacters(in: .whitespaces).isEmpty
            && !partnerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .fill(DS.parchment)
                    .frame(height: 220)
                    .overlay(
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DS.actionBlue)
                    )

                VStack(spacing: 6) {
                    Text("我们的小宇宙").dsHero()
                    Text("记录每一次见面、每一顿饭、每一种心情。\n数据只存在你的设备上。")
                        .dsCaption()
                        .multilineTextAlignment(.center)
                }

                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("阿铖", text: $myName)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    HStack {
                        Text("TA 的昵称").dsBody()
                        TextField("小于", text: $partnerName)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    DatePicker("在一起的日子", selection: $anniversary,
                               in: ...Date(), displayedComponents: .date)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }

                Button("创建我们的空间") {
                    try? CoupleRepository(context: context)
                        .bootstrapIfNeeded(myName: myName.trimmingCharacters(in: .whitespaces),
                                           partnerName: partnerName.trimmingCharacters(in: .whitespaces),
                                           anniversary: anniversary)
                }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.4)

                Text("P2 阶段这里会出现「接受 TA 的邀请」").dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
    }
}

#Preview {
    OnboardingView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
