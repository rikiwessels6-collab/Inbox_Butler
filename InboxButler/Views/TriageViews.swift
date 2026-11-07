import SwiftUI
import InboxButlerCore

/// "Remind me": quick presets plus a date and time picker.
struct ReminderSheet: View {
    let message: MailMessage
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Date().addingTimeInterval(3 * 3_600)
    @State private var showCustom = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remind me").font(.serif(.title)).foregroundStyle(Theme.ink)
                        Text(message.subject).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                    }

                    VStack(spacing: 0) {
                        let presets = TriageLogic.availablePresets()
                        ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                            let date = TriageLogic.date(for: preset)
                            Button { pick(date) } label: {
                                row(icon: preset.symbolName, title: preset.title,
                                    detail: date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Theme.hairline).padding(.leading, 64)
                            if index == presets.count - 1 { EmptyView() }
                        }
                        Button { withAnimation(.snappy) { showCustom.toggle() } } label: {
                            row(icon: "calendar.badge.clock", title: "Pick a date and time",
                                detail: showCustom ? "" : "", chevron: showCustom ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.plain)
                    }
                    .card(padding: 0)

                    if showCustom {
                        VStack(spacing: 14) {
                            DatePicker("When", selection: $custom, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                            Button("Set reminder") { pick(custom) }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        .card()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("The email leaves your inbox and comes back at the top at that time. Only inside Inbox Butler: your mailbox isn't changed.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(icon: String, title: String, detail: String, chevron: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.body).foregroundStyle(Theme.ink)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Theme.muted) }
            if let chevron { Image(systemName: chevron).font(.caption).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func pick(_ date: Date) {
        onPick(date)
        dismiss()
    }
}

/// "Marked done · Undo" banner.
struct UndoToastView: View {
    let toast: UndoToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text).font(.subheadline.weight(.medium))
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: 0xB9C0FF))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 20).padding(.vertical, 13)
        .background(Color(hex: 0x1B1B20).opacity(0.96), in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
