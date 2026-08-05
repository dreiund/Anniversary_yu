import SwiftUI

/// 加入确认页的出场判定。单测直调；nil id 必须返回 false（否则确认动作写不进有效 id，页面死循环）。
enum JoinNameConfirm {
    static func isNeeded(isParticipantDevice: Bool, coupleID: UUID?, confirmedCoupleID: String) -> Bool {
        guard isParticipantDevice, let id = coupleID else { return false }
        return id.uuidString != confirmedCoupleID
    }
}

/// 受邀方一次性确认页：TA 取的昵称在这里改成自己的（spec §二）。
/// 确认写入即置位 @AppStorage → RootView 观察到变化自动切主界面。
struct JoinNameConfirmView: View {
    @Environment(\.managedObjectContext) private var context
    let couple: CDCouple
    @AppStorage("nameConfirmedCoupleID") private var confirmedCoupleID = ""
    @State private var name = ""
    @State private var loaded = false

    private var canConfirm: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .fill(DS.parchment)
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(DS.actionBlue)
                    )

                VStack(spacing: 6) {
                    Text("欢迎加入我们的空间").dsHero()
                    Text("TA 给你取的昵称是「\(givenName)」。\n喜欢就直接确认，想改就改成你自己的。")
                        .dsCaption()
                        .multilineTextAlignment(.center)
                }

                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("", text: $name).multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }

                Button("就用这个昵称") { confirm() }
                    .buttonStyle(BluePillButtonStyle(fullWidth: true))
                    .disabled(!canConfirm)
                    .opacity(canConfirm ? 1 : 0.4)

                Text("以后只有你自己能改它").dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = givenName
        }
    }

    private var givenName: String {
        CoupleRepository(context: context).currentPartner(of: couple)?.name ?? ""
    }

    private func confirm() {
        let repo = CoupleRepository(context: context)
        // 伴侣记录未同步到位时不消费一次性确认页：静默不动，等同步好再点。
        guard let partner = repo.currentPartner(of: couple) else { return }
        partner.name = name.trimmingCharacters(in: .whitespaces)
        do {
            try context.save()
            confirmedCoupleID = couple.id?.uuidString ?? ""
        } catch {
            context.rollback()
        }
    }
}
