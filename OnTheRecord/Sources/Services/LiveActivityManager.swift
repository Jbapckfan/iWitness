import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct OnTheRecordAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var incidentID: String
        var startedAt: Date
        var elapsedSeconds: Int
        var estimatedSizeMB: Double
    }
}

@available(iOS 16.1, *)
enum LiveActivityRuntime {
    static var activity: Activity<OnTheRecordAttributes>?
}
#endif

/// Facade that no-ops when ActivityKit is unavailable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    func start(incidentID: String) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
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
        } else if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = OnTheRecordAttributes()
            let state = OnTheRecordAttributes.ContentState(
                incidentID: incidentID,
                startedAt: Date(),
                elapsedSeconds: 0,
                estimatedSizeMB: 0
            )
            do {
                LiveActivityRuntime.activity = try Activity<OnTheRecordAttributes>.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
            } catch {
                debugLog("[OnTheRecord] Live Activity start failed: \(error)")
            }
        }
        #endif
    }

    func update(elapsedSeconds: Int, estimatedSizeMB: Double) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
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
        } else if #available(iOS 16.1, *) {
            guard let activity = LiveActivityRuntime.activity else { return }
            let updatedState = OnTheRecordAttributes.ContentState(
                incidentID: activity.contentState.incidentID,
                startedAt: activity.contentState.startedAt,
                elapsedSeconds: elapsedSeconds,
                estimatedSizeMB: estimatedSizeMB
            )
            Task {
                await activity.update(using: updatedState)
            }
        }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                await LiveActivityRuntime.activity?.end(nil, dismissalPolicy: .immediate)
                LiveActivityRuntime.activity = nil
            }
        } else if #available(iOS 16.1, *) {
            Task {
                await LiveActivityRuntime.activity?.end(dismissalPolicy: .immediate)
                LiveActivityRuntime.activity = nil
            }
        }
        #endif
    }
}
