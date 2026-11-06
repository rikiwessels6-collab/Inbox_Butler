import SwiftUI
import WebKit

/// Shows an email's HTML safely:
///  - JavaScript is OFF;
///  - remote content (images, trackers, fonts) is BLOCKED unless the user allows it;
///  - tapped links open in Safari, never inside the message.
struct HTMLMessageView: UIViewRepresentable {
    let html: String
    let allowRemoteContent: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        let page = Self.wrap(html)
        let allow = allowRemoteContent
        Task { @MainActor in
            if !allow, let rules = try? await Self.blockEverythingRule() {
                web.configuration.userContentController.add(rules)
            }
            web.loadHTMLString(page, baseURL: nil)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private static func blockEverythingRule() async throws -> WKContentRuleList? {
        let json = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
        return try await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "block-all-remote", encodedContentRuleList: json)
    }

    private static func wrap(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { font-family: -apple-system, sans-serif; font-size: 17px; word-wrap: break-word; margin: 12px; }
        img { max-width: 100%; height: auto; }
        </style></head><body>\(html)</body></html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url,
                   ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    _ = await UIApplication.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }
    }
}

/// The sheet that hosts the formatted message.
struct HTMLMessageSheet: View {
    let subject: String
    let html: String
    @State private var allowRemote = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HTMLMessageView(html: html, allowRemoteContent: allowRemote)
                .id(allowRemote)   // reload when the setting changes
                .navigationTitle(subject)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allowRemote ? "Remote images on" : "Load remote images") { allowRemote.toggle() }
                    }
                }
        }
    }
}
