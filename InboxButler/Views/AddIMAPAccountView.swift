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
                        HStack {
                            SecureField(isICloud ? "App-specific password" : "Password", text: $password)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(14)
                    }
                    .card(padding: 0)

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.warn)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "First, make an app-specific password")
            VStack(alignment: .leading, spacing: 6) {
                Text("iCloud doesn't let apps use your Apple ID password. Create a special one:")
                    .font(.subheadline).foregroundStyle(Theme.ink)
                Text("1. Open appleid.apple.com and sign in\n2. Sign-In and Security > App-Specific Passwords\n3. Tap + , name it Inbox Butler, and copy the code (it looks like abcd-efgh-ijkl-mnop)")
                    .font(.footnote).foregroundStyle(Theme.muted)
                Link("Open appleid.apple.com", destination: URL(string: "https://appleid.apple.com")!)
                    .font(.footnote.weight(.semibold))
            }
            .card(padding: 14)
        }
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
