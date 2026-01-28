import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct IWitnessAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var incidentID: String
        var startedAt: Date
    }
}

@available(iOS 16.1, *)
enum LiveActivityRuntime {
    static var activity: Activity<IWitnessAttributes>?
}
#endif

/// Facade that no-ops when ActivityKit is unavailable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    func start(incidentID: String) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = IWitnessAttributes()
            let state = IWitnessAttributes.ContentState(incidentID: incidentID, startedAt: Date())
            let content = ActivityContent(state: state, staleDate: nil)
            do {
                LiveActivityRuntime.activity = try Activity<IWitnessAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("[OnTheRecord] Live Activity start failed: \(error)")
            }
        } else if #available(iOS 16.1, *) {
            // Fallback for iOS 16.1
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = IWitnessAttributes()
            let state = IWitnessAttributes.ContentState(incidentID: incidentID, startedAt: Date())
            do {
                LiveActivityRuntime.activity = try Activity<IWitnessAttributes>.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
            } catch {
                print("[OnTheRecord] Live Activity start failed: \(error)")
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
