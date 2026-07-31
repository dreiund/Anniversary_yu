import SwiftUI

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()
    @State private var loadedAnniversary: Date?

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

                Text("配对与同步在 P2 阶段开启 · 版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.parchment)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private func load() {
        guard let couple = couples.first else { return }
        let partners = CoupleRepository(context: context).partners(of: couple)
        myName = partners.first?.name ?? ""
        partnerName = partners.count > 1 ? (partners[1].name ?? "") : ""
        anniversary = couple.anniversaryDate ?? Date()
        loadedAnniversary = anniversary
    }

    private func save() {
        guard let couple = couples.first else { return }
        let partners = CoupleRepository(context: context).partners(of: couple)
        if !myName.trimmingCharacters(in: .whitespaces).isEmpty {
            partners.first?.name = myName
        }
        if partners.count > 1, !partnerName.trimmingCharacters(in: .whitespaces).isEmpty {
            partners[1].name = partnerName
        }
        try? context.save()
    }
}
