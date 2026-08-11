import SwiftUI

struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()
    @State private var createError: String?
    @State private var showAcceptGuide = false
    @State private var showAcceptFailed = false

    private var canCreate: Bool {
        !myName.trimmingCharacters(in: .whitespaces).isEmpty
            && !partnerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .fill(DS.parchment)
                    .frame(height: 220)
                    .overlay(
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DS.actionBlue)
                    )

                VStack(spacing: 6) {
                    Text("我们的小宇宙").dsHero()
                    Text("记录每一次见面、每一顿饭、每一种心情。\n数据只存在你的设备上。")
                        .dsCaption()
                        .multilineTextAlignment(.center)
                }

                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("阿铖", text: $myName)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    HStack {
                        Text("TA 的昵称").dsBody()
                        TextField("小于", text: $partnerName)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    DatePicker("在一起的日子", selection: $anniversary,
                               in: ...Date(), displayedComponents: .date)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }

                Button("创建我们的空间") {
                    do {
                        _ = try CoupleRepository(context: context)
                            .bootstrapIfNeeded(myName: myName.trimmingCharacters(in: .whitespaces),
                                               partnerName: partnerName.trimmingCharacters(in: .whitespaces),
                                               anniversary: anniversary)
                    } catch {
                        createError = "创建失败，请重试"
                    }
                }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.4)

                if let createError {
                    Text(createError)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.dsRed)
                }

                Button("接受邀请") { showAcceptGuide = true }
                    .buttonStyle(GhostPillButtonStyle())

                Text("TA 已经创建过空间？别再新建，用上面的接受邀请加入。")
                    .dsFootnote()
                    .multilineTextAlignment(.center)
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .sheet(isPresented: $showAcceptGuide) { AcceptInviteGuideSheet() }
        // P6-T4:本页正是"配对等待态"——couple 还没落地时 MainShell 不在场，
        // accept 失败的广播只有这里接得住，同样弹提示不静默吞错。
        .alert("接受邀请失败", isPresented: $showAcceptFailed) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("检查网络后重试，或让对方重新发一次邀请。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareAcceptFailed).receive(on: DispatchQueue.main)) { _ in
            showAcceptFailed = true
        }
    }
}

/// 接受方指引：接受动作本身由系统链接驱动（SceneDelegate），
/// 本页只负责讲清步骤并陪伴等待；共享数据一到、RootView 自动切主界面。
private struct AcceptInviteGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            let _ = couples.count  // 注册观察：共享空间导入后本 sheet 随 RootView 一起被替换
            Capsule().fill(DS.chipBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("加入 TA 的空间").dsPageTitle()
            VStack(alignment: .leading, spacing: 10) {
                Text("1. 让 TA 打开 App 设置 → 配对与同步，点「发出邀请」发给你").dsBody()
                Text("2. 微信里收到后:长按链接 → 「在 Safari 打开」;或从「信息」里直接点开").dsBody()
                Text("   (微信里直接点开会停在 iCloud 网页,完不成配对)").dsFootnote()
                Text("3. 回到这里稍等片刻，空间同步完成会自动进入").dsBody()
            }
            .padding(.horizontal, DS.Spacing.md)
            ProgressView()
            Text("等链接点开后，这里会自动完成").dsFootnote()
            Spacer()
            Button("知道了") { dismiss() }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .padding(.horizontal, DS.Spacing.md)
        }
        .padding(.bottom, DS.Spacing.lg)
        .presentationDetents([.medium])
        .background(DS.canvas)
    }
}

#Preview {
    OnboardingView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
