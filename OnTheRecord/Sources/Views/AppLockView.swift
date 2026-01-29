import SwiftUI
import LocalAuthentication

struct AppLockView: View {
    @ObservedObject var lockService: AppLockService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(UIColor.systemGray6).opacity(0.1))
                        .frame(width: 80, height: 80)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                        .shadow(color: Color.red.opacity(0.6), radius: 5)
                        .shadow(color: Color.red.opacity(0.25), radius: 12)
                        .shadow(color: Color.red.opacity(0.1), radius: 22)
                }

                VStack(spacing: 8) {
                    Text("OnTheRecord")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Locked")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if lockService.authenticationFailed {
                    Text("Authentication failed. Try again.")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button {
                    lockService.authenticate()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: lockService.biometricType == .faceID ? "faceid" : "touchid")
                        Text("Unlock with \(lockService.biometricName)")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(14)
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            lockService.authenticate()
        }
    }
}
