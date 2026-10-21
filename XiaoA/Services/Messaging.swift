import SwiftUI
import MessageUI
import UIKit

struct MessageDraft: Identifiable {
    let id = UUID()
    var recipients: [String]
    var body: String
    var imageJPEG: Data? = nil
}

/// The system Messages sheet, pre-filled so Mom only taps send.
struct MessageComposeView: UIViewControllerRepresentable {
    let draft: MessageDraft
    var onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = draft.recipients
        vc.body = draft.body
        if let data = draft.imageJPEG, MFMessageComposeViewController.canSendAttachments() {
            vc.addAttachmentData(data, typeIdentifier: "public.jpeg", filename: "photo.jpg")
        }
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void
        init(onFinish: @escaping (MessageComposeResult) -> Void) { self.onFinish = onFinish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(result)
        }
    }
}

enum Phone {
    static func digits(_ number: String) -> String {
        number.filter { "0123456789+".contains($0) }
    }

    /// Opens a URL that dials or texts. Tests replace it to record instead.
    static var open: (URL) -> Void = { UIApplication.shared.open($0) }

    static func call(_ number: String) {
        let d = digits(number)
        guard !d.isEmpty, let url = URL(string: "tel://\(d)") else { return }
        open(url)
    }

    /// Fallback when the Messages sheet isn't available (e.g. the simulator).
    static func openSMS(to number: String, body: String) {
        // "&", "+", "=", "?" and "#" would end or change the body (e.g. an address with "&").
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(digits(number))&body=\(encoded)") else { return }
        open(url)
    }
}
