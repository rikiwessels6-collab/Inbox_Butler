import SwiftUI
import InboxButlerCore

// MARK: - Backdrop

/// Soft pastel gradient with slowly drifting colour blooms.
struct PastelBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xEAF2FF), Color(hex: 0xF3EEFF), Color(hex: 0xFDF1F5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ZStack {
                        bloom(Color(hex: 0x9CC4FF), size: geo.size.width * 0.9,
                              x: geo.size.width * (0.25 + 0.08 * sin(t / 6)), y: geo.size.height * (0.30 + 0.06 * cos(t / 7)))
                        bloom(Color(hex: 0xC8A8FF), size: geo.size.width * 0.8,
                              x: geo.size.width * (0.78 + 0.07 * cos(t / 5)), y: geo.size.height * (0.62 + 0.07 * sin(t / 8)))
                        bloom(Color(hex: 0xFFC2D9), size: geo.size.width * 0.7,
                              x: geo.size.width * (0.40 + 0.09 * sin(t / 9)), y: geo.size.height * (0.92 + 0.04 * cos(t / 6)))
                    }
                }
            }
        }
    }

    private func bloom(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(color.opacity(0.55)).frame(width: size, height: size).blur(radius: 90).position(x: x, y: y)
    }
}

// MARK: - Practice emails

private struct PracticeMail: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    let subject: String
    let preview: String
    let time: String
}

private enum SwipeDirection { case right, left }

/// A fake email you can really swipe, to learn the gesture.
private struct PracticeRow: View {
    let mail: PracticeMail
    let direction: SwipeDirection
    let onSwiped: () -> Void
    @State private var dx: CGFloat = 0

    private var actionColor: Color { direction == .right ? Color(hex: 0x8A63D2) : Theme.good }

    var body: some View {
        ZStack {
            HStack {
                if direction == .left { Spacer() }
                Label(direction == .right ? "Remind" : "Done", systemImage: direction == .right ? "clock" : "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                if direction == .right { Spacer() }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(actionColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(abs(dx) > 6 ? 1 : 0)

            HStack(alignment: .top, spacing: 12) {
                Avatar(name: mail.sender, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(mail.sender).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(mail.time).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Text(mail.subject).font(.subheadline)
                    Text(mail.preview).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
            .offset(x: dx)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let t = value.translation.width
                        dx = direction == .right ? max(0, t) : min(0, t)
                    }
                    .onEnded { _ in
                        if abs(dx) > 110 {
                            withAnimation(.easeIn(duration: 0.18)) { dx = (direction == .right ? 1 : -1) * 700 }
                            Task {
                                try? await Task.sleep(nanoseconds: 180_000_000)
                                onSwiped()
                            }
                        } else {
                            withAnimation(.spring(duration: 0.3)) { dx = 0 }
                        }
                    }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: direction == .right ? "Remind me" : "Mark done") { onSwiped() }
    }
}

private struct SwipePracticePage: View {
    let direction: SwipeDirection
    @State private var mails: [PracticeMail]
    @State private var swiped = 0

    init(direction: SwipeDirection) {
        self.direction = direction
        _mails = State(initialValue: direction == .right ? [
            PracticeMail(sender: "Sophia Lamb", subject: "Can we talk Thursday?", preview: "No rush: whenever suits you this week.", time: "9:14 AM"),
            PracticeMail(sender: "Parcel Tracker", subject: "Your order is on its way", preview: "Arriving tomorrow between 9 and 5.", time: "8:40 AM")
        ] : [
            PracticeMail(sender: "Rahul Vohra", subject: "Quarterly review notes", preview: "Thanks everyone, all sorted on my side.", time: "9:02 AM"),
            PracticeMail(sender: "Team Newsletter", subject: "This week at the office", preview: "A quick round-up of what happened.", time: "7:55 AM")
        ])
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(mails) { mail in
                PracticeRow(mail: mail, direction: direction) {
                    withAnimation(.snappy) { mails.removeAll { $0.id == mail.id }; swiped += 1 }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if mails.isEmpty {
                Label(direction == .right ? "Reminder set. It'll be back when you're ready." : "Done. Out of your way.",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.good)
                    .padding(.top, 20)
                    .transition(.opacity)
            } else {
                Text("Try swiping the emails")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 14)
            }
        }
        .sensoryFeedback(.success, trigger: swiped)
    }
}

// MARK: - Tour

/// A short guided first run: the one-question idea, both swipes, what the assistant does,
/// an optional "about you" step, and a finish on the landscape.
struct OnboardingTourView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    @State private var page = 0
    @State private var questionIndex = 0
    @State private var jobTitle = ""
    @State private var organisation = ""
    @State private var about = ""

    private let pageCount = 6
    private var isLast: Bool { page == pageCount - 1 }

    var body: some View {
        ZStack {
            if isLast { WelcomeBackdrop().ignoresSafeArea().transition(.opacity) }
            else { PastelBackdrop().ignoresSafeArea().transition(.opacity) }

            if isLast {
                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Group {
                    switch page {
                    case 0: askPage
                    case 1: swipePage(.right)
                    case 2: swipePage(.left)
                    case 3: assistantPage
                    case 4: aboutYouPage
                    default: finishPage
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                bottomButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .preferredColorScheme(.light)
        .animation(.smooth(duration: 0.45), value: page)
        .task { await cycleQuestions() }
        .task {
            // Prefill from anything already saved.
            let saved = model.writerProfile
            jobTitle = saved.jobTitle; organisation = saved.organisation; about = saved.about
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? (isLast ? Color.white : Theme.accent) : (isLast ? Color.white.opacity(0.3) : Theme.hairline))
                        .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
            if !isLast {
                Button("Skip") { finish(saveProfile: false) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.white.opacity(0.8), in: Capsule())
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: 640)
    }

    private var bottomButton: some View {
        Button {
            if isLast { finish(saveProfile: false) }
            else {
                if page == 4 { saveProfile() }
                page += 1
            }
        } label: {
            Text(isLast ? "Done" : (page == 4 && hasProfileText ? "Save and continue" : "Continue"))
                .font(.headline)
                .foregroundStyle(isLast ? Color.white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isLast ? Color.white.opacity(0.22) : Color.white.opacity(0.85), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(isLast ? 0.5 : 0.9), lineWidth: 1))
        }
        .frame(maxWidth: 640)
    }

    // MARK: Pages

    private func headline(_ parts: [(String, Bool)], light: Bool = false) -> some View {
        var out = AttributedString()
        for (text, accent) in parts {
            var run = AttributedString(text)
            run.font = accent ? Font.system(.largeTitle, design: .serif).italic() : Font.system(.largeTitle, weight: .light)
            out += run
        }
        return Text(out)
            .foregroundStyle(light ? Color.white : Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var askPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("Every email comes down to one question").font(.title3).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 8) {
                question(0, [("Is it for ", false), ("today", true), ("?", false)])
                question(1, [("Can it ", false), ("wait", true), ("?", false)])
                question(2, [("Is it already ", false), ("done", true), ("?", false)])
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func question(_ index: Int, _ parts: [(String, Bool)]) -> some View {
        headline(parts).opacity(questionIndex == index ? 1 : 0.18).animation(.easeInOut(duration: 0.8), value: questionIndex)
    }

    private func swipePage(_ direction: SwipeDirection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer().frame(height: 18)
            if direction == .right {
                headline([("Swipe ", false), ("right", true), (" to set a reminder", false)])
                Text("The email leaves your inbox and comes back at the top when you're ready.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                headline([("Swipe ", false), ("left", true), (" to mark it done", false)])
                Text("Out of your inbox, still findable in Done or with search.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer().frame(height: 8)
            SwipePracticePage(direction: direction)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assistantPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 18)
            headline([("Your ", false), ("assistant", true), (" does the admin", false)])
            VStack(spacing: 12) {
                feature("sparkles", "Replies in your voice", "Drafted on this device from how you write. You review and send.")
                feature("calendar.badge.plus", "Events found for you", "Dates in emails and attachments become calendar suggestions you confirm.")
                feature("arrowshape.turn.up.left", "Nothing slips", "See who's waiting on you, and get nudged when someone hasn't replied.")
                feature("lock.shield", "Private by design", "Read-only access. Your mail is processed on your device.")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var aboutYouPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: 18)
                headline([("Help it sound like ", false), ("you", true)])
                Text("Optional. A little about you makes drafts more natural. It stays on this device.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    TextField("Job title", text: $jobTitle).padding(14)
                    Divider()
                    TextField("Company or organisation", text: $organisation).padding(14)
                    Divider()
                    TextField("What do you do? (one line)", text: $about, axis: .vertical).lineLimit(2...4).padding(14)
                }
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Theme.ink)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var finishPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            headline([("You'll get through your inbox ", false), ("twice", true), (" as fast.", false)], light: true)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
            Spacer().frame(height: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private var hasProfileText: Bool {
        ![jobTitle, organisation, about].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func saveProfile() {
        guard hasProfileText else { return }
        model.saveWriterProfile(WriterProfile(jobTitle: jobTitle, organisation: organisation, about: about))
    }

    private func finish(saveProfile shouldSave: Bool) {
        if shouldSave { saveProfile() }
        onFinish()
    }

    private func cycleQuestions() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            questionIndex = (questionIndex + 1) % 3
        }
    }
}
