import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct ReaderTTSActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var chapterName: String
        var progress: Double
        var isPaused: Bool
    }

    var novelName: String?
}

@MainActor
final class ReaderTTSLiveActivity {
    private var activity: Activity<ReaderTTSActivityAttributes>?

    func start(chapterName: String, novelName: String?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ReaderTTSActivityAttributes(novelName: novelName)
        let contentState = ReaderTTSActivityAttributes.ContentState(
            chapterName: chapterName,
            progress: 0,
            isPaused: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func update(chapterName: String, progress: Double, isPaused: Bool) async {
        guard let activity else { return }
        let contentState = ReaderTTSActivityAttributes.ContentState(
            chapterName: chapterName,
            progress: progress,
            isPaused: isPaused
        )
        await activity.update(ActivityContent(state: contentState, staleDate: nil))
    }

    func stop() async {
        guard let activity else { return }
        let contentState = ReaderTTSActivityAttributes.ContentState(
            chapterName: "",
            progress: 1,
            isPaused: false
        )
        await activity.end(ActivityContent(state: contentState, staleDate: nil), dismissalPolicy: .immediate)
        self.activity = nil
    }
}
#else
@MainActor
final class ReaderTTSLiveActivity {
    func start(chapterName: String, novelName: String?) async {}
    func update(chapterName: String, progress: Double, isPaused: Bool) async {}
    func stop() async {}
}
#endif
