import AppKit
import Sparkle

/// Wraps Sparkle's SPUStandardUpdaterController to provide auto-updates.
/// Reads SUFeedURL and SUPublicEDKey from the app's Info.plist.
///
/// In development (`swift run neetly-app`), Sparkle is disabled because the
/// executable doesn't run from a proper .app bundle and there's no SUFeedURL.
class Updater: NSObject {
    static let shared = Updater()

    private let updaterController: SPUStandardUpdaterController?

    /// True when running from a real .app bundle (with Sparkle Info.plist keys).
    static var isProductionBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    override init() {
        if Updater.isProductionBundle {
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            self.updaterController = nil
            NSLog("Updater: skipped (not running from a .app bundle)")
        }
        super.init()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        if let controller = updaterController {
            controller.checkForUpdates(sender)
        } else {
            NSLog("Updater: checkForUpdates ignored (dev mode)")
        }
    }
}
