import SwiftUI
import InboxButlerCore

/// Connects iCloud Mail (Apple ID email + app-specific password) or any IMAP server.
struct AddIMAPAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: AccountKind

    @State private var email = ""
    @State private var password = ""
    @State private var host = ""
    @State private var port = "993"
    @State private var username = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    private var isICloud: Bool { kind == .icloud }
    private var canConnect: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
            && (isICloud || !host.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isICloud ? "Add iCloud Mail" : "Add a mail account")
                            .font(.serif(.title)).foregroundStyle(Theme.ink)
                        Text("Read-only. Your password is saved in the iOS Keychain on this device only.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }

                    if isICloud { howTo }

                    VStack(spacing: 0) {
                        field("Email address", text: $email, content: .emailAddress)
                        if !isICloud {
                            divider
                            field("Server (e.g. imap.example.com)", text: $host, content: .URL)
                            divider
                            field("Port", text: $port, keyboard: .numberPad)
                            divider
                            field("Username (if different from email)", text: $username)
                        }
                        divider
                        HStack(spacing: 10) {
                            SecureField(isICloud ? "App-specific password" : "Password", text: $password)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if isICloud {
                                if looksLikeAppPassword {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                                        .accessibilityLabel("Looks like an app-specific password")
                                }
                                PasteButton(payloadType: String.self) { strings in
                                    if let first = strings.first {
                                        password = first.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }
                                .labelStyle(.titleOnly)
                                .buttonBorderShape(.capsule)
                                .tint(Theme.accent)
                            }
                        }
                        .padding(14)
                    }
                    .card(padding: 0)

                                if let errorText {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(Theme.warn)
                            if isICloud && !looksLikeAppPassword {
                                Text("Make sure you pasted the app-specific password (16 letters), not your normal Apple ID password.")
                                    .font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView().tint(.white) }
                            Text(isConnecting ? "Connecting…" : "Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canConnect || isConnecting)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .interactiveDismissDisabled(isConnecting)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Two minutes, one time")
            VStack(alignment: .leading, spacing: 14) {
                Text("Apple doesn't let apps use your Apple ID password, so you create a special one just for Inbox Butler.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                howStep(1, "Open your Apple Account page and sign in.")
                Link(destination: URL(string: "https://account.apple.com/account/manage")!) {
                    Label("Open Apple Account", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.leading, 36)
                howStep(2, "Choose Sign-In and Security, then App-Specific Passwords.")
                howStep(3, "Tap +, name it Inbox Butler, and copy the code Apple shows (like abcd-efgh-ijkl-mnop).")
                howStep(4, "Come back here and tap Paste below.")
            }
            .card(padding: 16)
        }
    }

    private func howStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.footnote.weight(.bold)).foregroundStyle(Color.white)
                .frame(width: 24, height: 24).background(Theme.accent, in: Circle())
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Apple's app-specific passwords look like abcd-efgh-ijkl-mnop.
    private var looksLikeAppPassword: Bool {
        let stripped = password.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        return stripped.count == 16 && stripped.allSatisfy { $0.isLetter }
    }

    private var divider: some View { Divider().overlay(Theme.hairline) }

    private func field(_ title: String, text: Binding<String>, content: UITextContentType? = nil,
                       keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(14)
    }

    private func connect() async {
        isConnecting = true
        errorText = nil
        defer { isConnecting = false }
        do {
            try await model.addIMAPAccount(kind: kind, email: email, password: password,
                                           host: host, port: Int(port) ?? 993, username: username)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
