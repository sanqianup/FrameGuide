import SwiftUI

@main
struct FrameGuideApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen().preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await PhotoRenderer.shared.clearCaches() }
                }
        }
    }
}
