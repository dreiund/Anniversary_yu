import SwiftUI

/// 反馈④：补录新开「过去的天」时选收尾时刻（预填当日 23:59，可跨午夜；确认即以此为该天封盘时间）
struct BackfillSealSheet: View {
    let day: Date
    let onConfirm: (Date) -> Void
    @State private var sealTime = Date()
    @State private var loaded = false

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("\(Fmt.monthDay.string(from: day)) 几点收的尾？").dsSectionTitle()
            Text("补录的这天还没有收尾时刻。选一个作为那天的封盘时间——之后这个时刻之前的补录都会归进这天。")
                .dsCaption()
            DatePicker("封盘时刻", selection: $sealTime,
                       in: dayStart...Calendar.current.date(byAdding: .hour, value: 36, to: dayStart)!)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("就这个时刻") { onConfirm(sealTime) }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(320)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            sealTime = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        }
    }
}

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
                SealReminder.refresh(context: context)
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
