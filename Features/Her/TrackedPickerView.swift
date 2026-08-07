import SwiftUI

/// 首次选人 / 设置改归属（spec §七）
struct TrackedPickerView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let couple: CDCouple
    @State private var picked: CDPartner?

    var body: some View {
        let partners = CoupleRepository(context: context).partners(of: couple)
        VStack(spacing: DS.Spacing.md) {
            Text("记录谁的经期？").dsPageTitle()
            Text("只问一次，设置里随时可改").dsFootnote()
            HStack(spacing: DS.Spacing.sm) {
                ForEach(partners, id: \.objectID) { partner in
                    Button {
                        picked = partner
                    } label: {
                        VStack(spacing: 8) {
                            AvatarInitial(name: partner.name ?? "", size: 48)
                            Text(partner.name ?? "").dsBody()
                        }
                        .padding(.vertical, 16).padding(.horizontal, 24)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.card)
                            .fill(DS.canvas))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card)
                            .stroke(picked?.objectID == partner.objectID ? DS.actionBlue : DS.chipBorder,
                                    lineWidth: picked?.objectID == partner.objectID ? 2 : 1))
                    }
                    .buttonStyle(DSPressEffect())
                }
            }
            Button("确定") {
                if let picked {
                    try? CycleRepository(context: context).setTracked(picked, couple: couple)
                    dismiss()
                }
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .disabled(picked == nil)
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
