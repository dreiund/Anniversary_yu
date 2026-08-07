import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @AppStorage("sealReminderOn") private var sealReminderOn = true
    @AppStorage("newMomentAlertOn") private var newMomentAlertOn = true
    @AppStorage("newLedgerAlertOn") private var newLedgerAlertOn = true
    @AppStorage("cycleStartAlertOn") private var cycleStartAlertOn = true
    @AppStorage("footprintsCycleTintOn") private var footprintsCycleTintOn = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()
    @State private var loadedAnniversary: Date?
    @StateObject private var sharing = SharingManager(controller: .shared)
    @State private var accountAvailable = true
    @State private var creatingShare = false
    @State private var confirmUnpair = false
    @State private var showTrackedPicker = false

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
                        if canEditPartnerNameNow {
                            TextField("", text: $partnerName).multilineTextAlignment(.trailing)
                                .onSubmit(save)
                        } else {
                            Spacer()
                            Text(partnerName).dsBody().foregroundStyle(DS.inkMuted)
                            Image(systemName: "lock")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.chipBorder)
                        }
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
                if !canEditPartnerNameNow {
                    Text("TA 的昵称由 TA 自己定").dsFootnote().padding(.horizontal, 4)
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
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    Toggle("TA 记了小本本", isOn: $newLedgerAlertOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    Toggle("经期开始提醒", isOn: $cycleStartAlertOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }

                Text("经期").dsSectionTitle()
                GroupedSection {
                    Button {
                        showTrackedPicker = true
                    } label: {
                        GroupedRow(title: "经期归属", value: trackedPartnerName, valueColor: DS.actionBlue)
                    }
                    .buttonStyle(.plain)
                    Toggle("足迹日历经期底色", isOn: $footprintsCycleTintOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }

                Text("配对与同步").dsSectionTitle()
                GroupedSection {
                    GroupedRow(title: "配对状态", value: pairingStatus.label,
                               valueColor: pairingStatus == .connected ? DS.dsGreen : DS.inkMuted)
                    if let couple = couples.first, !isParticipant {
                        switch pairingStatus {
                        case .notPaired:
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
                        case .invited:
                            if let url = sharing.share?.url {
                                ShareLink(item: url) {
                                    GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        case .connected:
                            if sharing.share?.publicPermission != CKShare.ParticipantPermission.none {
                                if let url = sharing.share?.url {
                                    ShareLink(item: url) {
                                        GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    Task { await sharing.lockInvites() }
                                } label: {
                                    GroupedRow(title: "对方已加入", value: "锁定邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    GroupedRow(title: "iCloud 账号", value: accountAvailable ? "正常" : "未登录",
                               valueColor: accountAvailable ? DS.dsGreen : DS.dsRed,
                               showsDivider: pairingStatus == .connected)
                    if pairingStatus == .connected {
                        Button { confirmUnpair = true } label: {
                            HStack {
                                Text("解除配对").dsBody().foregroundStyle(DS.dsRed)
                                Spacer()
                                Text("›").dsBody().foregroundStyle(DS.dsRed)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }
                        .buttonStyle(DSPressEffect())
                    }
                    if let error = sharing.lastError {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.dsRed)
                            .padding(.horizontal, 14).padding(.bottom, 8)
                    }
                }
                if pairingStatus == .connected {
                    Text(isParticipant
                         ? "解除配对后你的手机会清空这段空间；TA 的记录不受影响。"
                         : "解除配对后 TA 的手机会清空这段空间；你的记录全部保留。")
                        .dsFootnote().padding(.horizontal, 4)
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
        .sheet(isPresented: $showTrackedPicker) {
            if let couple = couples.first {
                TrackedPickerView(couple: couple, requireChoice: false)
            }
        }
        .alert("解除配对？", isPresented: $confirmUnpair) {
            Button("解除配对", role: .destructive) {
                guard let couple = couples.first else { return }
                let participant = isParticipant
                Task {
                    if participant {
                        await sharing.leaveSpace(for: couple)
                    } else {
                        await sharing.unpair(for: couple)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(unpairDialogMessage)
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
        if !partnerName.trimmingCharacters(in: .whitespaces).isEmpty, canEditPartnerNameNow {
            repo.otherPartner(of: couple)?.name = partnerName
        }
        try? context.save()
    }

    private var trackedPartnerName: String {
        guard let couple = couples.first else { return "未设置" }
        return CycleRepository(context: context).trackedPartner(couple: couple)?.name ?? "未设置"
    }

    private var isParticipant: Bool {
        guard let couple = couples.first else { return false }
        return CoupleRepository(context: context).isParticipantDevice(couple)
    }

    private var canEditPartnerNameNow: Bool {
        CoupleRepository.canEditPartnerName(isParticipantDevice: isParticipant,
                                            participantJoined: sharing.participantJoined)
    }

    private var pairingStatus: PairingStatus {
        SharingManager.pairingStatus(
            shareExists: sharing.share != nil,
            participantJoined: sharing.participantJoined,
            publicPermissionOpen: sharing.share?.publicPermission != CKShare.ParticipantPermission.none,
            isParticipantDevice: isParticipant)
    }

    /// 弹窗文案按角色（spec §一 文案照抄）
    private var unpairDialogMessage: String {
        isParticipant
            ? "解除后你的手机会清空这段空间并回到引导页；TA 那边的记录不受影响。想复合就让 TA 重新发邀请。"
            : "解除后 TA 的手机会清空这段空间并回到引导页；你的记录全部保留，重新发邀请可恢复。"
    }
}
