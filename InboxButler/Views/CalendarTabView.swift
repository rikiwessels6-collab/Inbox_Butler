import SwiftUI
import InboxButlerCore

/// Your real week, from every calendar on the device (iCloud, Google, family...), with events
/// found in your email shown as dashed suggestions. Read for display only.
struct CalendarTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var weekStart = CalendarTabView.startOfWeek(Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var events: [ExistingEvent] = []

    private let hourHeight: CGFloat = 56
    private let gutter: CGFloat = 46
    private var cal: Calendar { .current }

    var body: some View {
        NavigationStack {
            Group {
                if model.calendarAccess == .granted { content } else { permissionCard }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.refreshCalendars() }
        }
    }

    // MARK: Permission

    private var permissionCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("See your week here").font(.serif(.title))
            Text("Allow calendar access to see your events from iCloud, Google and family calendars next to your mail. Events found in emails appear as suggestions. Nothing from your calendar is stored or sent anywhere.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Allow calendar access") { Task { await model.requestCalendarAccess() } }
                .buttonStyle(PrimaryButtonStyle())
            if model.calendarAccess == .denied {
                Text("Access is off. Turn it on in Settings > Inbox Butler > Calendars.")
                    .font(.footnote).foregroundStyle(Theme.warn)
            }
        }
        .padding(32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Content

    private var days: [Date] {
        sizeClass == .compact ? [selectedDay] : (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            if sizeClass == .compact { dayStrip }
            dayHeaders
            allDayRow
            ScrollViewReader { proxy in
                ScrollView {
                    timeline
                        .padding(.bottom, 110)   // clear of the floating tab bar
                }
                .scrollIndicators(.hidden)
                .task(id: focusKey) {
                    // Wait a beat so the timeline has laid out, then land on "now" (today) or the
                    // first event of the chosen day, never on the empty small hours.
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.snappy) { proxy.scrollTo("hour-\(focusHour)", anchor: .top) }
                }
            }
        }
        .task(id: weekStart) { await load() }
        .onChange(of: model.calendarAccess) { _, _ in Task { await load() } }
    }

    private var focusKey: String { "\(selectedDay.timeIntervalSince1970)-\(events.count)" }

    private var focusHour: Int {
        let dayStart = cal.startOfDay(for: selectedDay)
        if cal.isDateInToday(selectedDay) { return min(max(cal.component(.hour, from: Date()) - 1, 0), 23) }
        if let first = clampedTimedEvents(on: dayStart).map({ cal.component(.hour, from: $0.start) }).min() {
            return max(first - 1, 0)
        }
        return 7
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekStart.formatted(.dateTime.month(.wide).year())).font(.serif(.title)).foregroundStyle(Theme.ink)
                Text(rangeText).font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Today") { goToToday() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
            Button { shift(by: -7) } label: { Image(systemName: "chevron.left") }
                .padding(8)
                .accessibilityLabel("Previous week")
            Button { shift(by: 7) } label: { Image(systemName: "chevron.right") }
                .padding(8)
                .accessibilityLabel("Next week")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var rangeText: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return weekStart.formatted(.dateTime.day().month(.abbreviated)) + " – " + end.formatted(.dateTime.day().month(.abbreviated))
    }

    /// iPhone: pick a day from the week.
    private var dayStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
                let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
                Button { withAnimation(.snappy) { selectedDay = cal.startOfDay(for: day) } } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold))
                        Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.white : (cal.isDateInToday(day) ? Theme.accent : Theme.ink))
                    .background(isSelected ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    /// iPad: weekday and date above each column.
    @ViewBuilder
    private var dayHeaders: some View {
        if sizeClass != .compact {
            HStack(spacing: 0) {
                Spacer().frame(width: gutter)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text(day.formatted(.dateTime.day()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(cal.isDateInToday(day) ? Color.white : Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(cal.isDateInToday(day) ? Theme.accent : Color.clear, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var allDayRow: some View {
        let hasAllDay = days.contains { !allDayEvents(on: $0).isEmpty }
        if hasAllDay {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day").font(.caption2).foregroundStyle(Theme.muted).frame(width: gutter)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 3) {
                        ForEach(allDayEvents(on: day)) { event in
                            Text(event.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(color(for: event).opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .frame(width: gutter, height: hourHeight, alignment: .topTrailing)
                        .padding(.trailing, 6)
                        .offset(y: -6)
                        .id("hour-\(hour)")
                }
            }
            .frame(width: gutter)
            ForEach(days, id: \.self) { day in dayColumn(day) }
        }
        .padding(.horizontal, 12)
    }

    private func dayColumn(_ day: Date) -> some View {
        let dayStart = cal.startOfDay(for: day)
        let placed = CalendarLayout.place(clampedTimedEvents(on: dayStart))
        let suggestions = model.suggestedEvents(from: dayStart, to: dayStart.addingTimeInterval(86_400))
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Spacer(minLength: 0).frame(height: hourHeight - 1)
                    }
                }
                ForEach(placed) { item in
                    let width = geo.size.width / CGFloat(item.laneCount)
                    eventBlock(item.event)
                        .frame(width: max(width - 3, 8), height: max(height(of: item.event), 22), alignment: .topLeading)
                        .offset(x: width * CGFloat(item.lane), y: y(of: item.event.start, dayStart: dayStart))
                }
                ForEach(suggestions, id: \.fingerprint) { suggestion in
                    suggestionBlock(suggestion)
                        .frame(width: max(geo.size.width - 6, 8), height: 30, alignment: .topLeading)
                        .offset(x: 2, y: y(of: suggestion.start, dayStart: dayStart))
                }
                if cal.isDateInToday(day) { nowLine(dayStart: dayStart, width: geo.size.width) }
            }
        }
        .frame(height: hourHeight * 24)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private func eventBlock(_ event: ExistingEvent) -> some View {
        let tint = color(for: event)
        return HStack(spacing: 0) {
            Rectangle().fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(event.start.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .background(tint.opacity(0.17), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)), \(event.calendarTitle)")
    }

    private func suggestionBlock(_ proposal: EventProposal) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles").font(.caption2)
            Text(proposal.title).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityLabel("Suggested from email: \(proposal.title)")
    }

    private func nowLine(dayStart: Date, width: CGFloat) -> some View {
        let offset = y(of: Date(), dayStart: dayStart)
        return ZStack(alignment: .leading) {
            Rectangle().fill(Color.red).frame(height: 1.5)
            Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4)
        }
        .frame(width: width)
        .offset(y: offset)
    }

    // MARK: Data and helpers

    private func load() async {
        let end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        events = await model.calendarEvents(from: weekStart, to: end)
    }

    private func allDayEvents(on day: Date) -> [ExistingEvent] {
        let start = cal.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        return events.filter { $0.isAllDay && $0.start < end && $0.end > start }
    }

    /// Timed events for one day, cut to that day's edges (so overnight events still lay out).
    private func clampedTimedEvents(on dayStart: Date) -> [ExistingEvent] {
        let dayEnd = dayStart.addingTimeInterval(86_400)
        return events.filter { !$0.isAllDay && $0.start < dayEnd && $0.end > dayStart }.map { e in
            ExistingEvent(id: e.id, title: e.title, calendarTitle: e.calendarTitle, start: max(e.start, dayStart),
                          end: min(e.end, dayEnd), isAllDay: false, colorHex: e.colorHex)
        }
    }

    private func y(of date: Date, dayStart: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3_600) * hourHeight
    }

    private func height(of event: ExistingEvent) -> CGFloat {
        CGFloat(event.end.timeIntervalSince(event.start) / 3_600) * hourHeight - 2
    }

    private func color(for event: ExistingEvent) -> Color {
        event.colorHex.map { Color(hex: $0) } ?? Theme.accent
    }

    private func hourLabel(_ hour: Int) -> String {
        hour == 0 ? "" : (cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date())
            .formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func shift(by days: Int) {
        withAnimation(.snappy) {
            weekStart = cal.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
            selectedDay = cal.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            weekStart = Self.startOfWeek(Date())
            selectedDay = cal.startOfDay(for: Date())
        }
    }

    static func startOfWeek(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}
