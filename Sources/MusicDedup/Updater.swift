import Combine
import Foundation
import Sparkle

/// Automatic updates through Sparkle, from the appcast published with each
/// GitHub release. Updates are verified with the app's own EdDSA key rather than
/// Apple notarization. Builds without a public key (SUPublicEDKey) leave it off.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: AnyCancellable?
    private(set) var canCheck = false

    var isAvailable: Bool { controller != nil }

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = key.isEmpty ? nil : SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // Sparkle's SwiftUI example uses assign(to: &$canCheck), which needs @Published.
        canCheckObservation = controller?.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set { withMutation(keyPath: \.automaticallyChecks) { controller?.updater.automaticallyChecksForUpdates = newValue } }
    }
}
