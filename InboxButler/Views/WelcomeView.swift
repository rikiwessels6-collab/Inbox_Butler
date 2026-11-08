import SwiftUI
import InboxButlerCore

// MARK: - Backdrop

/// A calm alpenglow landscape drawn in code: dusk sky, low sun, layered ridgelines and mist.
/// If you add an image named "WelcomeBackdrop" to the asset catalog it is used instead.
struct WelcomeBackdrop: View {
    var body: some View {
        if UIImage(named: "WelcomeBackdrop") != nil {
            GeometryReader { geo in
                Image("WelcomeBackdrop")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            drawn
        }
    }

    private struct Layer {
        let base: CGFloat        // ridge baseline, fraction of height
        let amplitude: CGFloat   // peak height, fraction of height
        let phase: CGFloat
        let color: Color
        let sharpness: CGFloat
    }

    private let layers: [Layer] = [
        Layer(base: 0.62, amplitude: 0.20, phase: 0.4, color: Color(hex: 0x9C7FA8), sharpness: 0.55),
        Layer(base: 0.68, amplitude: 0.24, phase: 2.1, color: Color(hex: 0x6E5A86), sharpness: 0.65),
        Layer(base: 0.76, amplitude: 0.22, phase: 4.0, color: Color(hex: 0x3F3A5F), sharpness: 0.75),
        Layer(base: 0.86, amplitude: 0.16, phase: 5.3, color: Color(hex: 0x1F2440), sharpness: 0.85),
        Layer(base: 0.96, amplitude: 0.10, phase: 1.2, color: Color(hex: 0x0E1226), sharpness: 0.95)
    ]

    private var drawn: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x1B1F4B), location: 0.0),
                .init(color: Color(hex: 0x4B3A7A), location: 0.28),
                .init(color: Color(hex: 0xC4688A), location: 0.52),
                .init(color: Color(hex: 0xF4A26B), location: 0.70),
                .init(color: Color(hex: 0xFFD79A), location: 0.80)
            ], startPoint: .top, endPoint: .bottom)

            // The low sun.
            RadialGradient(colors: [Color(hex: 0xFFE6B0).opacity(0.95), Color(hex: 0xFFB070).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.68, y: 0.60), startRadius: 4, endRadius: 520)
                .blendMode(.screen)

            Canvas { context, size in
                for (index, layer) in layers.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    let steps = 140
                    for i in 0...steps {
                        let x = CGFloat(i) / CGFloat(steps)
                        let ridge = ridgeHeight(x, layer)
                        path.addLine(to: CGPoint(x: x * size.width, y: (layer.base - ridge) * size.height))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [layer.color, layer.color.opacity(0.92)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                    // Mist settling between ridges.
                    if index < layers.count - 1 {
                        let mist = Path(CGRect(x: 0, y: (layer.base - 0.02) * size.height, width: size.width, height: 0.16 * size.height))
                        context.fill(mist, with: .linearGradient(
                            Gradient(colors: [.clear, Color(hex: 0xFFD9C0).opacity(0.16 - Double(index) * 0.025), .clear]),
                            startPoint: CGPoint(x: 0, y: (layer.base - 0.02) * size.height),
                            endPoint: CGPoint(x: 0, y: (layer.base + 0.14) * size.height)))
                    }
                }
            }
            .blur(radius: 0.4)
        }
    }

    /// Jagged mountain profile built from a few folded sine waves.
    private func ridgeHeight(_ x: CGFloat, _ layer: Layer) -> CGFloat {
        func fold(_ v: CGFloat) -> CGFloat { 1 - abs(sin(v)) }   // sharp peaks, soft valleys
        let main = fold(x * 5.0 + layer.phase)
        let mid = fold(x * 11.0 + layer.phase * 1.7) * 0.45
        let fine = fold(x * 27.0 + layer.phase * 0.6) * 0.14
        let smooth = (sin(x * 3.0 + layer.phase) + 1) / 2
        let sharp = main * 0.65 + mid + fine
        let blended = layer.sharpness * sharp + (1 - layer.sharpness) * smooth
        return blended * layer.amplitude
    }
}

// MARK: - Glass buttons

/// Translucent "liquid glass" button (iOS 26), or a frosted capsule on older systems.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .contentShape(Capsule())
        Group {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                label.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                label.background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
            }
            #else
            label.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
            #endif
        }
        .opacity(configuration.isPressed ? 0.8 : 1)
        .scaleEffect(configuration.isPressed ? 0.985 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Welcome

/// First-run screen: a full-bleed landscape, the wordmark, and glass sign-in buttons.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @State private var appeared = false
    @State private var drift = false
    @State private var isSigningIn = false
    @State private var showICloud = false
    @State private var message: String?

    var body: some View {
        ZStack {
            WelcomeBackdrop()
                .scaleEffect(drift && !reduceMotion ? 1.07 : 1.0)
                .offset(x: drift && !reduceMotion ? -14 : 0)
                .ignoresSafeArea()

            // Soft shade so the white text and buttons always read clearly.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.0), location: 0.0),
                .init(color: .black.opacity(0.10), location: 0.55),
                .init(color: Color(hex: 0x071321).opacity(0.92), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                brand
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                Spacer()
                buttons
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: 480)
        }
        .preferredColorScheme(.dark)
        .accessibilityAddTraits(.isModal)   // VoiceOver ignores everything behind the welcome screen
        .task {
            withAnimation(.easeOut(duration: 1.0)) { appeared = true }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) { drift = true }
        }
        .sheet(isPresented: $showICloud) { AddIMAPAccountView(kind: .icloud) }
        .alert("Couldn't connect", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
        // Any account being added (Google or iCloud) ends the welcome.
        .onChange(of: model.usingDemoData) { _, isDemo in if !isDemo { onFinish() } }
    }

    /// The butler mark is intentionally drawn in SwiftUI so it scales cleanly
    /// and does not require a third-party brand asset.
    private var butlerMark: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.8), lineWidth: 1.5)
                .frame(width: 102, height: 102)
            Image(systemName: "person.crop.square.filled.and.at.rectangle")
                .font(.system(size: 43, weight: .ultraLight))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Image(systemName: "envelope.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .offset(x: 34, y: 17)
        }
        .accessibilityLabel("Inbox Butler emblem")
    }

    private var brand: some View {
        VStack(spacing: 13) {
            butlerMark
                .padding(.bottom, 10)
            Text("Inbox Butler")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text("YOUR PERSONAL EMAIL ASSISTANT")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2.1)
                .foregroundStyle(Theme.accent)
            Text("Your inbox, thoughtfully handled.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    private var buttons: some View {
        VStack(spacing: 14) {
            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    if isSigningIn { ProgressView().tint(.white) }
                    Text("Continue with Google")
                }
            }
            .buttonStyle(GlassButtonStyle())
            .accessibilityIdentifier("welcome-google")
            .disabled(isSigningIn)

            Button { showICloud = true } label: { Text("Continue with iCloud") }
                .buttonStyle(GlassButtonStyle())
                .accessibilityIdentifier("welcome-icloud")

            Button {
                AppRouter.shared.tab = .accounts
                onFinish()
            } label: {
                Text("Outlook and other accounts")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(.top, 4)

            Button(action: onFinish) {
                Text("Look around with demo mail")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityIdentifier("welcome-demo")
        }
    }

    private func signInWithGoogle() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await model.addGmailAccount()
        } catch let error as SignInError {
            if case .failed(let text) = error { message = text }   // cancelled = silent
        } catch {
            message = error.localizedDescription
        }
    }
}
