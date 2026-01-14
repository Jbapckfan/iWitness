import SwiftUI

@main
struct iWitnessWatchApp: App {
    @StateObject private var watchState = WatchState()
    @StateObject private var connectivityManager = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchState)
                .environmentObject(connectivityManager)
                .onAppear {
                    connectivityManager.activate()
                }
        }
    }
}
