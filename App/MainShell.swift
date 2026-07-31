import SwiftUI
import CoreData

enum AppTab {
    case us
    case footprints
}

struct MainShell: View {
    @Environment(\.managedObjectContext) private var context
    @State private var tab: AppTab = .us
    @State private var showPanel = false
    @State private var activeSheet: ShellSheet?
    @State private var pendingAction: PanelAction?
    @State private var showNoMeetingAlert = false

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "statusRaw == %d", MeetingStatus.ongoing.rawValue)
    ) private var ongoingMeetings: FetchedResults<CDMeeting>

    enum ShellSheet: Identifiable {
        case newMoment(CDMeeting)
        case mood
        case seal(CDMeeting)

        var id: String {
            switch self {
            case .newMoment: "newMoment"
            case .mood: "mood"
            case .seal: "seal"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tab {
                case .us: NavigationStack { HomeView() }
                case .footprints: NavigationStack { MeetingsView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showPanel, onDismiss: {
            if let action = pendingAction {
                pendingAction = nil
                handle(action)
            }
        }) {
            ActionPanel(hasOngoing: ongoingMeetings.first != nil) { action in
                pendingAction = action
                showPanel = false
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newMoment(let meeting):
                MomentFormView(mode: .create(meeting))
            case .mood:
                if let couple = try? CoupleRepository(context: context).fetchCouple() {
                    MoodSheet(couple: couple)
                }
            case .seal(let meeting):
                SealSheet(meeting: meeting)
            }
        }
        .alert("还没有进行中的见面", isPresented: $showNoMeetingAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("去足迹页开始一次见面，再来记录。")
        }
    }

    private func handle(_ action: PanelAction) {
        switch action {
        case .newMoment:
            if let meeting = ongoingMeetings.first { activeSheet = .newMoment(meeting) } else { showNoMeetingAlert = true }
        case .mood:
            activeSheet = .mood
        case .seal:
            if let meeting = ongoingMeetings.first { activeSheet = .seal(meeting) }
        }
    }

    private var bottomBar: some View {
        FrostedBottomBar {
            HStack {
                tabButton("我们", tab: .us)
                Spacer()
                tabButton("足迹", tab: .footprints)
                Spacer()
                Button {
                    showPanel = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(DS.actionBlue))
                        .rotationEffect(.degrees(showPanel ? 45 : 0))
                        .animation(.easeOut(duration: 0.2), value: showPanel)
                }
                .buttonStyle(DSPressEffect())
                .offset(y: -8)
                Spacer()
                disabledTab("小本本")
                Spacer()
                disabledTab("她")
            }
        }
    }

    private func tabButton(_ title: String, tab target: AppTab) -> some View {
        Button {
            tab = target
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == target ? .semibold : .regular))
                .foregroundStyle(tab == target ? DS.actionBlue : DS.inkMuted)
        }
        .buttonStyle(DSPressEffect())
    }

    private func disabledTab(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(DS.inkMuted)
            .opacity(0.35)
    }
}
