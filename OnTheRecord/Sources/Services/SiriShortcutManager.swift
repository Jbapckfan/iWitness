import Foundation
import Intents
import IntentsUI

/// Manages Siri Shortcuts for voice activation
/// User can say "Hey Siri, [custom phrase]" to activate OnTheRecord
class SiriShortcutManager: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = SiriShortcutManager()

    // MARK: - Activity Types

    static let activateActivityType = "com.ontherecord.activate"
    static let safeActivityType = "com.ontherecord.safe"
    static let pulledOverActivityType = "com.ontherecord.pulledover"

    // MARK: - Published State

    @Published var isShortcutDonated: Bool = false

    // MARK: - Donate Shortcuts

    /// Donate the "Put this on the record" shortcut to Siri
    func donateActivateShortcut() {
        let activity = NSUserActivity(activityType: Self.activateActivityType)
        activity.title = "Put This On The Record"
        activity.suggestedInvocationPhrase = "Put this on the record"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = Self.activateActivityType

        // Make it available
        activity.becomeCurrent()

        isShortcutDonated = true
        debugLog("[OnTheRecord] Siri shortcut donated: Put this on the record")
    }

    /// Donate the "I'm being pulled over" shortcut to Siri
    func donatePulledOverShortcut() {
        let activity = NSUserActivity(activityType: Self.pulledOverActivityType)
        activity.title = "I'm Being Pulled Over"
        activity.suggestedInvocationPhrase = "I'm being pulled over"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = Self.pulledOverActivityType

        activity.becomeCurrent()
        debugLog("[OnTheRecord] Siri shortcut donated: I'm being pulled over")
    }

    /// Donate the "I'm Safe" shortcut to Siri
    func donateSafeShortcut() {
        let activity = NSUserActivity(activityType: Self.safeActivityType)
        activity.title = "I'm Safe"
        activity.suggestedInvocationPhrase = "I'm Safe"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = Self.safeActivityType

        activity.becomeCurrent()
        debugLog("[OnTheRecord] Siri shortcut donated: I'm Safe")
    }

    // MARK: - Handle Shortcuts

    /// Handle incoming Siri shortcut activation
    /// Returns true if the activity was handled
    func handleUserActivity(_ activity: NSUserActivity) -> Bool {
        switch activity.activityType {
        case Self.activateActivityType:
            NotificationCenter.default.post(name: .siriActivateWitness, object: nil)
            return true

        case Self.pulledOverActivityType:
            NotificationCenter.default.post(name: .siriActivateWitness, object: nil)
            return true

        case Self.safeActivityType:
            NotificationCenter.default.post(name: .siriMarkSafe, object: nil)
            return true

        default:
            return false
        }
    }

    // MARK: - Check Shortcut Status

    func checkShortcutStatus() {
        // Check if shortcuts have been added by user
        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { shortcuts, error in
            guard let shortcuts = shortcuts else { return }

            let hasActivate = shortcuts.contains { shortcut in
                shortcut.shortcut.userActivity?.activityType == Self.activateActivityType
            }

            DispatchQueue.main.async {
                self.isShortcutDonated = hasActivate
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siriActivateWitness = Notification.Name("siriActivateWitness")
    static let siriMarkSafe = Notification.Name("siriMarkSafe")
}

// MARK: - Add Shortcut Button View

import SwiftUI

struct AddToSiriButton: View {
    let activityType: String
    let title: String
    let phrase: String

    @State private var showingAddSheet = false

    var body: some View {
        Button {
            showingAddSheet = true
        } label: {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.white)
                Text("Add to Siri")
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black)
            .cornerRadius(20)
        }
        .sheet(isPresented: $showingAddSheet) {
            SiriShortcutSheet(activityType: activityType, title: title, phrase: phrase)
        }
    }
}

struct SiriShortcutSheet: UIViewControllerRepresentable {
    let activityType: String
    let title: String
    let phrase: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = title
        activity.suggestedInvocationPhrase = phrase
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true

        let shortcut = INShortcut(userActivity: activity)
        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        viewController.delegate = context.coordinator

        let navigationController = UINavigationController(rootViewController: viewController)
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, INUIAddVoiceShortcutViewControllerDelegate {
        func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
            controller.dismiss(animated: true)
        }

        func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
            controller.dismiss(animated: true)
        }
    }
}
