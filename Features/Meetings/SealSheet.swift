import SwiftUI

struct SealSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    @State private var sealTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("封盘").dsSectionTitle()
            Text("今天到此为止，晚安。").dsCaption()
            DatePicker("封盘时刻", selection: $sealTime)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("确认封盘") {
                try? MeetingRepository(context: context).sealOpenDay(in: meeting, at: sealTime)
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(280)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}
