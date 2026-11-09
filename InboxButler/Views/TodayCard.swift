import SwiftUI
import InboxButlerCore

/// "Today" at the top of the inbox: the few things that need you, in one glance.
/// Tapping a row that came from an email opens that email.
struct TodayCard: View {
    let brief: TodayBrief
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill").foregroundStyle(Theme.gold)
                Text("Today").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.bottom, 10)

            ForEach(Array(brief.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Theme.hairline) }
                row(item)
            }
        }
        .card(padding: 16)
        .accessibilityIdentifier("today-card")
    }

    @ViewBuilder
    private func row(_ item: TodayBrief.Item) -> some View {
        let content = HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(item.kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint(item.kind))
                .frame(width: 28, height: 28)
                .background(tint(item.kind).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                Text(item.detail).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if item.messageID != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 6)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        if let id = item.messageID {
            Button { onOpen(id) } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private func symbol(_ kind: TodayBrief.Kind) -> String {
        switch kind {
        case .allDay: return "sparkle"
        case .event: return "calendar"
        case .clash: return "exclamationmark.2"
        case .suggestion: return "calendar.badge.plus"
        case .security: return "lock.shield"
        case .bill: return "doc.text"
        case .reply: return "arrowshape.turn.up.left"
        }
    }

    private func tint(_ kind: TodayBrief.Kind) -> Color {
        switch kind {
        case .allDay: return Theme.gold
        case .event: return Theme.accent
        case .clash: return Theme.warn
        case .suggestion: return Theme.accent
        case .security: return Theme.warn
        case .bill: return Theme.gold
        case .reply: return Theme.good
        }
    }
}
