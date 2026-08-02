import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @AppStorage("sealReminderOn") private var sealReminderOn = true
    @AppStorage("newMomentAlertOn") private var newMomentAlertOn = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()
    @State private var loadedAnniversary: Date?
    @StateObject private var sharing = SharingManager(controller: .shared)
    @State private var accountAvailable = true
    @State private var creatingShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("我们的资料").dsSectionTitle()
                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("", text: $myName).multilineTextAlignment(.trailing)
                            .onSubmit(save)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    HStack {
                        Text("TA 的昵称").dsBody()
                        TextField("", text: $partnerName).multilineTextAlignment(.trailing)
                            .onSubmit(save)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    DatePicker("在一起的日子", selection: $anniversary,
                               in: ...Date(), displayedComponents: .date)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .onChange(of: anniversary) { _, newValue in
                            guard let baseline = loadedAnniversary, newValue != baseline else { return }
                            couples.first?.anniversaryDate = newValue
                            try? context.save()
                            loadedAnniversary = newValue
                        }
                }

                Text("显示").dsSectionTitle()
                GroupedSection {
                    Toggle("首页倒计时", isOn: $showCountdown)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }

                Text("通知").dsSectionTitle()
                GroupedSection {
                    Toggle("封盘提醒", isOn: $sealReminderOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .onChange(of: sealReminderOn) { _, _ in
                            SealReminder.refresh(context: context)
                        }
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    Toggle("新记忆提醒", isOn: $newMomentAlertOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }

                Text("配对与同步").dsSectionTitle()
                GroupedSection {
                    GroupedRow(title: "配对状态", value: pairingStatusText,
                               valueColor: pairingStatusDone ? DS.dsGreen : DS.inkMuted)
                    if let couple = couples.first,
                       !CoupleRepository(context: context).isParticipantDevice(couple) {
                        if let url = sharing.share?.url {
                            ShareLink(item: url) {
                                GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                            }
                            .buttonStyle(.plain)
                            if sharing.participantJoined, sharing.share?.publicPermission != CKShare.ParticipantPermission.none {
                                Button {
                                    Task { await sharing.lockInvites() }
                                } label: {
                                    GroupedRow(title: "对方已加入", value: "锁定邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Button {
                                creatingShare = true
                                Task {
                                    defer { creatingShare = false }
                                    _ = try? await sharing.ensureShare(for: couple)
                                }
                            } label: {
                                GroupedRow(title: "还没配对", value: creatingShare ? "生成中…" : "生成邀请 ›",
                                           valueColor: DS.actionBlue)
                            }
                            .buttonStyle(.plain)
                            .disabled(creatingShare)
                        }
                    }
                    GroupedRow(title: "iCloud 账号", value: accountAvailable ? "正常" : "未登录",
                               valueColor: accountAvailable ? DS.dsGreen : DS.dsRed, showsDivider: false)
                    if let error = sharing.lastError {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.dsRed)
                            .padding(.horizontal, 14).padding(.bottom, 8)
                    }
                }

                Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.parchment)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .task {
            if let couple = couples.first {
                await sharing.loadShare(for: couple)
            }
            let status = try? await CKContainer(identifier: PersistenceController.cloudContainerID).accountStatus()
            accountAvailable = status == .available
        }
        .onDisappear(perform: save)
    }

    private func load() {
        guard let couple = couples.first else { return }
        let repo = CoupleRepository(context: context)
        myName = repo.currentPartner(of: couple)?.name ?? ""
        partnerName = repo.otherPartner(of: couple)?.name ?? ""
        anniversary = couple.anniversaryDate ?? Date()
        loadedAnniversary = anniversary
    }

    private func save() {
        guard let couple = couples.first else { return }
        let repo = CoupleRepository(context: context)
        if !myName.trimmingCharacters(in: .whitespaces).isEmpty {
            repo.currentPartner(of: couple)?.name = myName
        }
        if !partnerName.trimmingCharacters(in: .whitespaces).isEmpty {
            repo.otherPartner(of: couple)?.name = partnerName
        }
        try? context.save()
    }

    private var pairingStatusText: String {
        guard let couple = couples.first else { return "未配对" }
        if CoupleRepository(context: context).isParticipantDevice(couple) { return "已连接" }
        if sharing.participantJoined { return "已连接" }
        if sharing.share != nil { return "邀请已发出" }
        return "未配对"
    }

    private var pairingStatusDone: Bool { pairingStatusText == "已连接" }
}
