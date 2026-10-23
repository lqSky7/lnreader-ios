#if os(iOS)
import UIKit

final class TTSAudioAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        LibraryMaintenance.register()
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == "com.lnreader.audio.downloads.v1" else { completionHandler(); return }
        TTSOfflineLibrary.shared.backgroundCompletion = completionHandler
        TTSOfflineLibrary.shared.reconnectBackgroundSession()
    }
}
#endif
