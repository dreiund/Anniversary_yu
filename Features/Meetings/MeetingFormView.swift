import SwiftUI

enum MeetingFormMode {
    case create(CDCouple)
    case edit(CDMeeting)
}

struct MeetingFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: MeetingFormMode
    @State private var title = ""
    @State private var city = ""
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.startOfDay(for: Date())
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editingMeeting: CDMeeting? {
        if case .edit(let m) = mode { return m }
        return nil
    }

    private var editingStatus: MeetingStatus {
        editingMeeting.map { MeetingRepository(context: context).status(of: $0) } ?? .planned
    }

    /// 进行中只有实际开始可改（还没结束，无结束日期可言）
    private var showsEndDate: Bool { editingStatus != .ongoing }

    private var dateLabels: (start: String, end: String) {
        editingStatus == .planned ? ("开始日期", "结束日期") : ("实际开始", "实际结束")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    GroupedSection {
                        HStack {
                            Text("标题").dsBody()
                            TextField("可选，如 上海行", text: $title).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        HStack {
                            Text("城市").dsBody()
                            TextField("可选", text: $city).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        DatePicker(dateLabels.start, selection: $start, displayedComponents: .date)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        if showsEndDate {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            DatePicker(dateLabels.end, selection: $end, in: start..., displayedComponents: .date)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }

                    if editingMeeting != nil, editingStatus == .planned {
                        GroupedSection {
                            Button { confirmDelete = true } label: {
                                Text("删除这次计划").dsBody()
                                    .foregroundStyle(DS.dsRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(DSPressEffect())
                        }
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(editingMeeting == nil ? "计划见面" : "编辑见面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .confirmationDialog("删除这次计划？行前计划的日程会一起删除。",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除计划", role: .destructive) {
                    if let m = editingMeeting {
                        try? MeetingRepository(context: context).deletePlanned(m)
                    }
                    dismiss()
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !loaded, let m = editingMeeting else { return }
        loaded = true
        title = m.title ?? ""
        city = m.city ?? ""
        switch editingStatus {
        case .planned:
            start = m.plannedStart ?? start
            end = m.plannedEnd ?? end
        case .ongoing:
            start = m.startedAt ?? start
        case .finished:
            start = m.startedAt ?? start
            end = m.endedAt ?? end
        }
    }

    private func save() {
        let t = title.isEmpty ? nil : title
        let c = city.isEmpty ? nil : city
        switch mode {
        case .create(let couple):
            try? MeetingRepository(context: context).createPlanned(
                couple: couple, title: t, city: c, plannedStart: start, plannedEnd: end)
        case .edit(let m):
            try? MeetingRepository(context: context).update(
                m, title: t, city: c, start: start, end: showsEndDate ? end : nil)
        }
        dismiss()
    }
}
