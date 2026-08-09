import SwiftUI
import CoreData

/// 反馈⑧:时间线里的计划卡三态
enum PlanCardState {
    case todo       // 进行中待办:虚线框+空圈,点圈转化
    case prepared   // 行前已备:划线+实勾,纯记录
    case missed     // 结束后没做成:灰卡
}

struct PlanTodoCard: View {
    @Environment(\.managedObjectContext) private var context
    let item: CDPlanItem
    let state: PlanCardState
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch state {
            case .todo:
                Button { onToggle?() } label: {
                    Circle().strokeBorder(DS.inkMuted, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("划掉 \(item.title ?? "")")
            case .prepared:
                ZStack {
                    Circle().fill(DS.chipBorder).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            case .missed:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state == .todo ? DS.ink : DS.inkMuted)
                    .strikethrough(state == .prepared)
                if let sub = subtitle {
                    Text(sub).dsFootnote()
                }
            }
            Spacer(minLength: 0)
            if state == .missed {
                Text("没做成 · 下次再来")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.inkMuted)
                    .padding(.vertical, 2).padding(.horizontal, 7)
                    .overlay(Capsule().stroke(DS.chipBorder, lineWidth: 1))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let moment = PlanItemRepository(context: context).plannedMoment(of: item) {
            let prefix = state == .missed ? "原定 " : ""
            let text = item.time == nil ? Fmt.monthDayWeek.string(from: moment)
                : "\(Fmt.monthDayWeek.string(from: moment)) \(Fmt.hm.string(from: moment))"
            parts.append(prefix + text)
        }
        if let placeName = item.place?.name ?? item.placeText, !placeName.isEmpty {
            parts.append(placeName)
        }
        if state != .prepared, let note = item.note, !note.isEmpty {
            parts.append("备注:\(note)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var background: some View {
        switch state {
        case .todo:
            RoundedRectangle(cornerRadius: DS.Radius.darkCard)
                .fill(DS.canvas.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard)
                    .strokeBorder(DS.chipBorder, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        case .prepared:
            RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.parchment.opacity(0.9))
        case .missed:
            RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.chipBorder.opacity(0.35))
        }
    }
}
