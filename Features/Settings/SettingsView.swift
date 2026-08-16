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
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
    @State private var myName = ""
    @State private var showDiagnostics = false
    @State private var showInviteShare = false
    @State private var inviteCopied = false
    @State private var orphanAuthors = 0
    @State private var confirmRepairAuthors = false
    @State private var confirmPrunePlaces = false
    @State private var orphanPlaces = 0
    @State private var partnerName = ""
    @State private var anniversary = Date()
    @State private var loadedAnniversary: Date?
    @StateObject private var sharing = SharingManager(controller: .shared)
    @State private var accountAvailable = true
    @State private var creatingShare = false
    @State private var confirmUnpair = false
    @State private var showTrackedPicker = false
    @State private var editingCyclePref: CyclePrefKind?

    /// R20 经期设置:滚轮 sheet 的目标字段
    enum CyclePrefKind: String, Identifiable {
        case cycleLength, periodLength
        var id: String { rawValue }
    }

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
                    Button {
                        editingCyclePref = .cycleLength
                    } label: {
                        GroupedRow(title: "月经周期", value: cyclePrefValue(isCycle: true), valueColor: DS.actionBlue)
                    }
                    .buttonStyle(.plain)
                    Button {
                        editingCyclePref = .periodLength
                    } label: {
                        GroupedRow(title: "经期长度", value: cyclePrefValue(isCycle: false), valueColor: DS.actionBlue)
                    }
                    .buttonStyle(.plain)
                    Toggle("足迹日历周期底色", isOn: $footprintsCycleTintOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
                Text("手动选定天数后始终按所选值预测；选「自动」则记满 2 个完整周期按 TA 的实际记录推算（显示「按记录」），数据不足时用默认 28/7。")
                    .dsFootnote()
                    .padding(.horizontal, 14)

                Text("配对与同步").dsSectionTitle()
                GroupedSection {
                    // P6-B1:双 couple 歧义防线的最后一道——理论上 pruneEmptyLocalCouple 该已经
                    // 自愈掉多余空间，这行只在自愈没跑到/没赶上时兜底，提示用户找开发者别自己瞎点。
                    if couples.count > 1 {
                        Button { showDiagnostics = true } label: {
                            GroupedRow(title: "检测到重复空间", value: "点击诊断 ›", valueColor: DS.dsOrange)
                        }
                        .buttonStyle(.plain)
                    }
                    // 反馈:选点地图冒旧钉=孤儿地点(引用删光地点残留;启动自动清扫因云同步竞态已撤,
                    // 手动入口在数据完整时由用户主动触发,无竞态风险)
                    if orphanPlaces > 0 {
                        Button { confirmPrunePlaces = true } label: {
                            GroupedRow(title: "无引用的旧地点", value: "清理 \(orphanPlaces) 个 ›", valueColor: DS.dsOrange)
                        }
                        .buttonStyle(.plain)
                    }
                    if orphanAuthors > 0 {
                        Button { confirmRepairAuthors = true } label: {
                            GroupedRow(title: "作者显示异常的记录", value: "修复 \(orphanAuthors) 条 ›", valueColor: DS.dsOrange)
                        }
                        .buttonStyle(.plain)
                    }
                    GroupedRow(title: "配对状态", value: pairingStatus.label,
                               valueColor: pairingStatus == .connected ? DS.dsGreen : DS.inkMuted)
                    if let couple = couples.first, !isParticipant {
                        switch pairingStatus {
                        case .notPaired:
                            Button {
                                creatingShare = true
                                Task {
                                    defer { creatingShare = false }
                                    // 反馈⑮bug1:成功直接弹分享面板(此前只是行文案静默变化,像没反应);失败设 lastError 可见
                                    if await sharing.generateInvite(for: couple) { showInviteShare = true }
                                }
                            } label: {
                                GroupedRow(title: "还没配对", value: creatingShare ? "生成中…" : "生成邀请 ›",
                                           valueColor: DS.actionBlue)
                            }
                            .buttonStyle(.plain)
                            .disabled(creatingShare)
                        case .invited:
                            if let url = sharing.share?.url {
                                // 反馈⑮bug3:载荷=带指引文字(微信内置浏览器打不开配对,须 Safari/信息)
                                ShareLink(item: SharingManager.inviteMessage(url: url)) {
                                    GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    UIPasteboard.general.string = SharingManager.inviteMessage(url: url)
                                    inviteCopied = true
                                } label: {
                                    GroupedRow(title: "或复制邀请文字", value: inviteCopied ? "已复制 ✓" : "复制 ›",
                                               valueColor: inviteCopied ? DS.dsGreen : DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        case .connected:
                            // 反馈⑯bug3:「锁定邀请」移除——经公开链接加入的参与者会随公开权限
                            // 一起被关在门外(锁门=踢人=配对解除,实测事故)。安全模型改为链接保密。
                            GroupedRow(title: "对方已加入", value: "链接勿外传", valueColor: DS.inkMuted)
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
                if pairingStatus == .invited {
                    Text("对方在微信里收到后:长按链接 → 选「在 Safari 打开」;或让 TA 从「信息」App 里点开。微信里直接点会停在 iCloud 网页,完不成配对。")
                        .dsFootnote().padding(.horizontal, 4)
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
        .sheet(isPresented: $showDiagnostics) { CoupleDiagnosticsView() }
        .sheet(isPresented: $showInviteShare) {
            if let url = sharing.share?.url {
                InviteActivityView(text: SharingManager.inviteMessage(url: url))
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            orphanPlaces = PlacePruner.orphanCount(context: context)
            if let couple = couples.first {
                orphanAuthors = CoupleRepository(context: context).orphanAuthorCount(of: couple)
            }
        }
        .alert("把 \(orphanAuthors) 条记录归为你记的?", isPresented: $confirmRepairAuthors) {
            Button("归为我记的", role: .destructive) {
                if let couple = couples.first {
                    _ = try? CoupleRepository(context: context).repairOrphanAuthors(of: couple)
                    orphanAuthors = CoupleRepository(context: context).orphanAuthorCount(of: couple)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些记录的作者信息指向早前被删除的空间成员,目前显示成「TA 记的」。只在确认这些是你本人在这台设备上写的时执行;TA 写的同类记录请在 TA 的手机上执行同样修复。")
        }
        .alert("清理 \(orphanPlaces) 个无引用地点?", isPresented: $confirmPrunePlaces) {
            Button("清理", role: .destructive) {
                PlacePruner.pruneOrphans(context: context)
                orphanPlaces = PlacePruner.orphanCount(context: context)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些地点没有任何记忆、小本本、日程或待办引用,只在选点地图里残留旧钉。清理后即从选点中消失,不影响任何现有数据。")
        }
        .sheet(isPresented: $showTrackedPicker) {
            if let couple = couples.first {
                TrackedPickerView(couple: couple, requireChoice: false)
            }
        }
        .sheet(item: $editingCyclePref) { kind in
            if let couple = couples.first {
                CyclePrefPickerSheet(kind: kind, couple: couple)
                    .presentationDetents([.height(340)])
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

    /// R20-②:行上显示当前生效值与来源——手动=「n 天」;自动挡=「按记录 · n 天」(满 2 个完整周期)
    /// 或「默认 · 28/7 天」(数据不足)
    private func cyclePrefValue(isCycle: Bool) -> String {
        guard let couple = couples.first else { return "—" }
        let stored = isCycle ? couple.cycleLengthPref : couple.periodLengthPref
        if stored > 0 { return "\(stored) 天" }
        let inputs = CycleRepository(context: context).cyclesSorted(couple: couple)
            .compactMap { c -> (start: Date, end: Date?)? in c.startDate.map { ($0, c.endDate) } }
        let p = CyclePredictor.predict(cycles: inputs, prefs: couple.cyclePrefs,
                                       today: Date(), calendar: .current)
        if let learned = isCycle ? p.learnedCycleLength : p.learnedPeriodLength {
            return "按记录 · \(learned) 天"
        }
        return "默认 · \(isCycle ? 28 : 7) 天"
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


/// 反馈⑮bug1:生成邀请成功后直接弹出的系统分享面板(UIKit 桥;ShareLink 无法程序化触发)
private struct InviteActivityView: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_: UIActivityViewController, context: Context) {}
}

/// R20 经期设置滚轮(月经周期 20–45 天 / 经期长度 2–10 天):存 CDCouple 走 CloudKit,两台手机预测一致
private struct CyclePrefPickerSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let kind: SettingsView.CyclePrefKind
    @ObservedObject var couple: CDCouple
    @State private var value = 28

    private var isCycle: Bool { kind == .cycleLength }
    private var range: ClosedRange<Int> { isCycle ? 20...45 : 2...10 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isCycle ? "月经周期" : "经期长度").dsSectionTitle()
                Spacer()
                Button("完成") {
                    if isCycle { couple.cycleLengthPref = Int16(value) }
                    else { couple.periodLengthPref = Int16(value) }
                    try? context.save()
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.actionBlue)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, 18)
            Picker(isCycle ? "月经周期" : "经期长度", selection: $value) {
                Text("自动 · 按记录").tag(0)                    // 0=自动挡:满 2 个完整周期按记录,不足用 28/7
                ForEach(range, id: \.self) { Text("\($0) 天").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 190)
            Text(isCycle
                 ? "从这次月经第一天到下次第一天的间隔。手动选定始终生效;排卵按「下次开始日 − 14 天」推算，周期多长都科学适配。"
                 : "每次行经持续的天数，用于画预测区间的长短。手动选定始终生效。")
                .dsFootnote()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, 16)
        }
        .background(DS.canvas)
        .onAppear {
            value = Int(isCycle ? couple.cycleLengthPref : couple.periodLengthPref)   // 0=自动
        }
    }
}
