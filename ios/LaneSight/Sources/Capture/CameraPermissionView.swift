import SwiftUI

/// The camera permission surfaces (v3.7 Figma 466:3811 pre-prompt / 466:3877 denied). Shown in place of
/// the viewfinder: a priming screen before the iOS prompt, and an honest "camera is off" screen after a
/// denial (with Upload-a-video as the fallback path).
struct CameraPermissionView: View {
    enum Mode { case prompt, denied }
    let mode: Mode
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().strokeBorder(LS.action.opacity(0.5), lineWidth: 2).frame(width: 84, height: 84)
                Image(systemName: mode == .prompt ? "camera.fill" : "video.slash.fill")
                    .font(.system(size: 30)).foregroundStyle(LS.action)
            }
            Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).padding(.top, 16)
            Text(message).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8).padding(.horizontal, 24)
            Spacer()
            Button { onPrimary() } label: {
                HStack(spacing: 8) { Text(primaryLabel); Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold)) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(secondaryLabel) { onSecondary() }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(LS.link).padding(.top, 10)
        }
        .padding(.horizontal, 24).padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LSBackground())
    }

    private var title: String { mode == .prompt ? "Allow camera access" : "Camera is off for LaneSight" }
    private var message: String {
        mode == .prompt
            ? "LaneSight records each shot or delivery to measure it. Clips are analyzed, then the raw video is deleted after 30 days (change this in Settings)."
            : "To record shots, turn on Camera in iPhone Settings › LaneSight. You can still analyze a video from Photos."
    }
    private var primaryLabel: String { mode == .prompt ? "Continue" : "Open Settings" }
    private var secondaryLabel: String { mode == .prompt ? "Not now" : "Upload a video instead" }
}
