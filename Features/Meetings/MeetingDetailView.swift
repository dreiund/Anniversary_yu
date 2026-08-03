import SwiftUI

struct MeetingDetailView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @State private var segment = 0
    @State private var confirmEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(meeting.index) 次见面\(meeting.city.map { " · \($0)" } ?? "")").dsFootnote()
                }
                Spacer()
                HStack(spacing: 4) {
                    SelectableChip(title: "时间线", isSelected: segment == 0) { segment = 0 }
                    SelectableChip(title: "计划", isSelected: segment == 1) { segment = 1 }
                }
            }
            .padding(DS.Spacing.md)

            if segment == 0 {
                ScrollView {
                    TimelineListView(meeting: meeting)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                }
            } else {
                PlanView(meeting: meeting)
            }
        }
        .background(DS.parchment)
        .navigationTitle(meeting.title ?? meeting.city ?? "见面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if meeting.statusRaw == MeetingStatus.ongoing.rawValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("结束见面") { confirmEnd = true }
                        .font(.system(size: 14))
                }
            }
        }
        .confirmationDialog("结束这次见面？未封盘的天会一并封盘。",
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("结束见面", role: .destructive) {
                try? MeetingRepository(context: context).end(meeting, at: Date())
                SealReminder.refresh(context: context)
            }
        }
    }
}
