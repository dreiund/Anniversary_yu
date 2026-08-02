import SwiftUI
import PhotosUI

enum MomentFormMode {
    case create(CDMeeting)
    case edit(CDMoment)
}

struct MomentFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: MomentFormMode

    @State private var type: MomentType = .restaurant
    @State private var title = ""
    @State private var bodyText = ""
    @State private var happenedAt = Date()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var stars = 0
    @State private var moodEmoji: String?
    @State private var comment = ""
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locating = false
    @State private var staleDay: CDDateDay?

    private var isEdit: Bool { if case .edit = mode { true } else { false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    typeChips
                    if !isEdit { photoSection }
                    fieldsSection
                    if !isEdit { evaluationSection; locationSection }
                    if isEdit { Text("照片、评价与地点暂不支持修改").dsFootnote() }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(isEdit ? "编辑记忆" : "新的记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存储") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
            .onChange(of: pickerItems) { _, items in
                Task {
                    var datas: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    photoDatas = datas
                }
            }
            .sheet(item: $staleDay) { day in
                StaleSealSheet(day: day) { sealTime in
                    if case let .create(meeting) = mode {
                        try? MeetingRepository(context: context).sealOpenDay(in: meeting, at: sealTime)
                        doCreate(in: meeting)
                    }
                }
            }
        }
    }

    private var typeChips: some View {
        HStack(spacing: 6) {
            ForEach(MomentType.allCases, id: \.rawValue) { t in
                SelectableChip(title: t.title, isSelected: type == t) { type = t }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                Text(photoDatas.isEmpty ? "选择照片" : "已选 \(photoDatas.count) 张")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.actionBlue)
            }
            if !photoDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                            if let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }

    private var fieldsSection: some View {
        GroupedSection {
            HStack {
                Text("标题").dsBody()
                TextField("如 蟹家大院", text: $title).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            DS.hairline.frame(height: 1).padding(.leading, 14)
            DatePicker("时刻", selection: $happenedAt)
                .padding(.horizontal, 14).padding(.vertical, 6)
            DS.hairline.frame(height: 1).padding(.leading, 14)
            VStack(alignment: .leading, spacing: 4) {
                Text("正文 · 共同记事（可选）").dsFootnote()
                TextField("发生了什么…", text: $bodyText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private var evaluationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("你的评价").dsFootnote()
            StarInputView(stars: $stars)
            EmojiPickerRow(selection: $moodEmoji)
            TextField("短评：一句话点评（可选）", text: $comment)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }

    private var locationSection: some View {
        GroupedSection {
            HStack {
                Text("地点").dsBody()
                TextField("可选", text: $locationName).multilineTextAlignment(.trailing)
                Button(locating ? "定位中" : "定位") {
                    locating = true
                    Task {
                        if let result = try? await LocationFetcher().fetch() {
                            locationName = result.name
                            coords = (result.latitude, result.longitude)
                        }
                        locating = false
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(DS.actionBlue)
                .disabled(locating)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private func loadIfEditing() {
        guard case let .edit(moment) = mode else { return }
        type = MomentType(rawValue: moment.typeRaw) ?? .other
        title = moment.title ?? ""
        bodyText = moment.body ?? ""
        happenedAt = moment.happenedAt ?? Date()
    }

    private func save() {
        switch mode {
        case let .edit(moment):
            try? MomentRepository(context: context).update(
                moment, type: type, title: title,
                body: bodyText.isEmpty ? nil : bodyText, happenedAt: happenedAt)
            dismiss()
        case let .create(meeting):
            let stale = (try? MeetingRepository(context: context).staleOpenDay(in: meeting, now: Date())) ?? nil
            if let stale {
                staleDay = stale
                return
            }
            doCreate(in: meeting)
        }
    }

    private func doCreate(in meeting: CDMeeting) {
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let authorID = couple.flatMap { couples.currentPartnerID(of: $0) }

        var place: CDPlace?
        if !locationName.trimmingCharacters(in: .whitespaces).isEmpty, let couple {
            let p = CDPlace(context: context)
            p.id = UUID()
            p.name = locationName
            p.latitude = coords?.0 ?? 0
            p.longitude = coords?.1 ?? 0
            p.createdAt = Date()
            p.couple = couple
            place = p
        }

        let evaluation = stars > 0 || moodEmoji != nil || !comment.isEmpty
            ? NewEvaluation(stars: Int16(stars), moodEmoji: moodEmoji,
                            comment: comment.isEmpty ? nil : comment)
            : nil

        _ = try? MomentRepository(context: context).create(
            in: meeting, type: type, title: title,
            body: bodyText.isEmpty ? nil : bodyText,
            happenedAt: happenedAt, photoDatas: photoDatas,
            myEvaluation: evaluation, authorID: authorID, place: place)
        SealReminder.refresh(context: context)
        dismiss()
    }
}

extension CDDateDay: Identifiable {}
