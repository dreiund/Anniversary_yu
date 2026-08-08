import SwiftUI
import PhotosUI
import CoreData

enum QuickLedgerMode {
    case create(CDCouple)
    case edit(CDLedgerEntry)
}

/// 喜怒轻表单（spec §七，小样选 B 整页同构精简版）。佐证最多 1 张，happenedAt = 保存时刻。
struct QuickLedgerSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: QuickLedgerMode

    @State private var category: LedgerCategory = .like
    @State private var title = ""
    @State private var note = ""
    @State private var visibility: EntryVisibility = .sharedImmediately
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var evidencesToDelete: [CDEvidence] = []
    @State private var confirmReveal = false
    @State private var loaded = false

    private var editingEntry: CDLedgerEntry? {
        if case .edit(let entry) = mode { return entry }
        return nil
    }
    private var visibilityLocked: Bool {
        guard let entry = editingEntry else { return false }
        return LedgerRules.isRevealed(visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt)
    }
    private var existingEvidence: CDEvidence? {
        guard let entry = editingEntry else { return nil }
        return LedgerRepository(context: context).evidencesSorted(entry)
            .filter { !evidencesToDelete.contains($0) }.first
    }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: 8) {
                        typeCard(.like, symbol: "❤", accent: DS.dsGreen)
                        typeCard(.trigger, symbol: "⚡", accent: DS.dsOrange)
                    }

                    GroupedSection {
                        TextField("一句话说清楚，比如「吃完饭会自然牵手」", text: $title)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                    }

                    GroupedSection {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 1, matching: .images) {
                            HStack {
                                Text("佐证照片").dsBody()
                                Spacer()
                                Text(photoDatas.isEmpty && existingEvidence == nil ? "＋ 添加" : "已有 1 张")
                                    .dsCaption()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }
                        if let evidence = existingEvidence, photoDatas.isEmpty,
                           let data = evidence.thumbnailData, let ui = UIImage(data: data) {
                            HStack {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                Button("移除") { evidencesToDelete.append(evidence) }
                                    .font(.system(size: 12)).foregroundStyle(DS.dsRed)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.bottom, 11)
                        }
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        HStack {
                            Text("备注").dsBody()
                            TextField("可选", text: $note).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        Toggle("私密", isOn: Binding(
                            get: { visibility == .privateUntilRevealed },
                            set: { newValue in
                                // 编辑中把已私密条目关成公开＝一次性公开仪式，先确认（spec §三/§七）
                                if !newValue, editingEntry != nil, !visibilityLocked,
                                   visibility == .privateUntilRevealed {
                                    confirmReveal = true
                                } else {
                                    visibility = newValue ? .privateUntilRevealed : .sharedImmediately
                                }
                            }))
                            .disabled(visibilityLocked)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                    }

                    Text(visibilityLocked
                         ? "已公开，不可改回私密"
                         : "开着=公开前只有你看得到")
                        .dsFootnote().padding(.horizontal, 4)
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(editingEntry == nil ? "记一条喜怒" : "编辑喜怒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
            }
            .onChange(of: pickerItems) {
                Task {
                    var datas: [Data] = []
                    for item in pickerItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    photoDatas = datas
                }
            }
            .alert("公开给 TA？", isPresented: $confirmReveal) {
                Button("公开") { visibility = .sharedImmediately }
                Button("取消", role: .cancel) {}
            } message: {
                Text("公开后 TA 会看到这条，且不可撤回。")
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func typeCard(_ target: LedgerCategory, symbol: String, accent: Color) -> some View {
        Button {
            category = target
        } label: {
            Text("\(symbol) \(target.title)")
                .font(.system(size: 14, weight: category == target ? .semibold : .regular))
                .foregroundStyle(category == target ? accent : DS.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(category == target ? accent : DS.chipBorder,
                            lineWidth: category == target ? 1.5 : 1))
        }
        .buttonStyle(DSPressEffect())
    }

    private func loadIfNeeded() {
        guard !loaded, let entry = editingEntry else { return }
        loaded = true
        category = LedgerCategory(rawValue: entry.categoryRaw) ?? .like
        title = entry.title ?? ""
        note = entry.detail ?? ""
        // 同互评表单：锁定态强制显示「公开」（reveal 不改 visibilityRaw）
        visibility = visibilityLocked ? .sharedImmediately
            : (EntryVisibility(rawValue: entry.visibilityRaw) ?? .sharedImmediately)
    }

    private func save() {
        let repo = LedgerRepository(context: context)
        let couples = CoupleRepository(context: context)
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create(let couple):
            let authorID = couples.currentPartnerID(of: couple)
            _ = try? repo.createEntry(couple: couple, category: category, title: trimmedTitle,
                                      detail: trimmedNote.isEmpty ? nil : trimmedNote,
                                      happenedAt: Date(), visibility: visibility,
                                      place: nil, evidenceDatas: photoDatas, authorID: authorID)
        case .edit(let entry):
            try? repo.updateEntry(entry, category: category, title: trimmedTitle,
                                  detail: trimmedNote.isEmpty ? nil : trimmedNote,
                                  happenedAt: entry.happenedAt ?? Date(), place: nil)
            for evidence in evidencesToDelete { try? repo.deleteEvidence(evidence) }
            if !photoDatas.isEmpty {
                // 佐证限 1 张：有新图则旧图全清再写
                for evidence in repo.evidencesSorted(entry) {
                    try? repo.deleteEvidence(evidence)
                }
                try? repo.addEvidences(entry, datas: photoDatas)
            }
            if !visibilityLocked, visibility == .sharedImmediately,
               entry.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
                try? repo.reveal(entry, at: Date())
            }
        }
        dismiss()
    }
}
