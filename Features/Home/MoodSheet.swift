import SwiftUI

struct MoodSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let couple: CDCouple
    @State private var emoji: String?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("今日心情").dsSectionTitle()
            EmojiPickerRow(selection: $emoji)
            TextField("想说一句吗（可选）", text: $note)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("保存") {
                if let emoji {
                    let repo = CoupleRepository(context: context)
                    try? DailyMoodRepository(context: context).setMood(
                        couple: couple, authorID: repo.creatorID(of: couple),
                        day: Date(), emoji: emoji,
                        note: note.isEmpty ? nil : note, calendar: .current)
                }
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .disabled(emoji == nil)
            .opacity(emoji == nil ? 0.4 : 1)
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
        .onAppear {
            let repo = CoupleRepository(context: context)
            if let existing = DailyMoodRepository(context: context).mood(
                couple: couple, authorID: repo.creatorID(of: couple), day: Date(), calendar: .current) {
                emoji = existing.moodEmoji
                note = existing.note ?? ""
            }
        }
    }
}
