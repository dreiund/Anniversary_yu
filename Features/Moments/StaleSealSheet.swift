import SwiftUI

struct StaleSealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: CDDateDay
    let onConfirm: (Date) -> Void
    @State private var sealTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("昨天忘了封盘？").dsSectionTitle()
            Text("第 \(day.dayIndex) 天还开着。先补个封盘时刻，这条新记录会归入新的一天。").dsCaption()
            DatePicker("封盘时刻", selection: $sealTime)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("补封并继续") {
                onConfirm(sealTime)
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}
