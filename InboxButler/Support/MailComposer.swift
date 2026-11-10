import SwiftUI
import MessageUI

/// The system "new message" sheet, pre-filled with a reviewed draft. NOTHING is sent until the
/// user taps Send in this sheet themselves.
struct MailComposer: UIViewControllerRepresentable {
    let to: [String]
    let subject: String
    let body: String
    let preferredFrom: String?
    /// An optional attachment, e.g. the calendar reply for an invite.
    var attachment: (data: Data, mimeType: String, fileName: String)? = nil
    let onFinish: (MFMailComposeResult) -> Void

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let preferredFrom { vc.setPreferredSendingEmailAddress(preferredFrom) }
        if let attachment { vc.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName) }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.onFinish(result) }
        }
    }
}
