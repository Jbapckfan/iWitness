import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct OnTheRecordAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var incidentID: String
        var startedAt: Date
        var elapsedSeconds: Int
        var estimatedSizeMB: Double
    }
}

enum LiveActivityRuntime {
    static var activity: Activity<OnTheRecordAttributes>?
}
#endif

/// Facade that no-ops when ActivityKit is unavailable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    func start(incidentID: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = OnTheRecordAttributes()
        let state = OnTheRecordAttributes.ContentState(
            incidentID: incidentID,
            startedAt: Date(),
            elapsedSeconds: 0,
            estimatedSizeMB: 0
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            LiveActivityRuntime.activity = try Activity<OnTheRecordAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            debugLog("[OnTheRecord] Live Activity start failed: \(error)")
        }
        #endif
    }

    func update(elapsedSeconds: Int, estimatedSizeMB: Double) {
        #if canImport(ActivityKit)
        guard let activity = LiveActivityRuntime.activity else { return }
        let updatedState = OnTheRecordAttributes.ContentState(
            incidentID: activity.content.state.incidentID,
            startedAt: activity.content.state.startedAt,
            elapsedSeconds: elapsedSeconds,
            estimatedSizeMB: estimatedSizeMB
        )
        let content = ActivityContent(state: updatedState, staleDate: nil)
        Task {
            await activity.update(content)
        }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        Task {
            await LiveActivityRuntime.activity?.end(nil, dismissalPolicy: .immediate)
            LiveActivityRuntime.activity = nil
        }
        #endif
    }
}
