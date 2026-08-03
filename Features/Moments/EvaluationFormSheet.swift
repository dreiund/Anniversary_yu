import SwiftUI

/// 给一条记忆补/改"我这一半"的评价。两台设备同一套代码：
/// authorID 由 currentPartnerID 解析，她的设备写她那半。
struct EvaluationFormSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let moment: CDMoment
    @State private var stars = 5
    @State private var moodEmoji: String?
    @State private var comment = ""
    @State private var saveFailed = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Capsule().fill(DS.chipBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("我的评价").dsPageTitle()
            ParchmentCard {
                VStack(alignment: .leading, spacing: 12) {
                    StarInputView(stars: $stars)
                    EmojiPickerRow(selection: $moodEmoji)
                    TextField("一句话短评（可选）", text: $comment)
                        .textFieldStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            Button("保存") {
                let couples = CoupleRepository(context: context)
                guard let couple = try? couples.fetchCouple() else { return }
                do {
                    try MomentRepository(context: context).upsertEvaluation(
                        on: moment,
                        by: couples.currentPartnerID(of: couple),
                        NewEvaluation(stars: Int16(stars), moodEmoji: moodEmoji,
                                      comment: comment.isEmpty ? nil : comment))
                    dismiss()
                } catch {
                    saveFailed = true
                }
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .padding(.horizontal, DS.Spacing.md)
            if saveFailed {
                Text("保存失败，请重试").font(.system(size: 13)).foregroundStyle(DS.dsRed)
            }
            Spacer()
        }
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
        .presentationDetents([.medium])
        .background(DS.canvas)
    }
}
