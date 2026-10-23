import SwiftUI
import MessageUI
import UIKit

enum Route: Hashable {
    case look
    case ask
    case interpreter
    case ride
    case emergency(practice: Bool)
    case call911(practice: Bool)
    case medical
    case addressCard(Place?)
    case alex
}

@MainActor
final class AppState: ObservableObject {
    @Published var path: [Route] = []
    @Published var messageDraft: MessageDraft?
    /// Photo handed from Lesen to Fragen.
    var pendingAskImage: UIImage?
    /// Called when the Messages sheet closes (sent or cancelled).
    private var onMessageFinished: ((Bool) -> Void)?

    func go(_ route: Route) { path.append(route) }
    func home() { path.removeAll() }

    func ask(about image: UIImage?) {
        pendingAskImage = image
        go(.ask)
    }

    /// Opens a pre-filled text message. She only has to tap send.
    func text(_ number: String, body: String, image: Data? = nil, onFinish: ((Bool) -> Void)? = nil) {
        if MFMessageComposeViewController.canSendText() {
            onMessageFinished = onFinish
            messageDraft = MessageDraft(recipients: [Phone.digits(number)], body: body, imageJPEG: image)
        } else {
            Phone.openSMS(to: number, body: body)
            onFinish?(true)
        }
    }

    func messageFinished(_ result: MessageComposeResult) {
        messageDraft = nil
        onMessageFinished?(result == .sent)
        onMessageFinished = nil
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack(path: $app.path) {
            HomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    if case .alex = route {
                        // Alex's settings use a normal iOS navigation bar.
                        AlexModeView()
                    } else {
                        destination(route)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationBarBackButtonHidden(true)
                    }
                }
        }
        .sheet(item: $app.messageDraft) { draft in
            MessageComposeView(draft: draft) { result in app.messageFinished(result) }
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .look: LookView()
        case .ask: AskView()
        case .interpreter: InterpreterView()
        case .ride: RideView()
        case .emergency(let practice): EmergencyView(practice: practice)
        case .call911(let practice): Call911View(practice: practice)
        case .medical: MedicalCardView()
        case .addressCard(let place): AddressCardView(place: place)
        case .alex: AlexModeView()
        }
    }
}
