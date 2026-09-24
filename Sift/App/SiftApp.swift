import SwiftUI

@main
struct SiftApp: App {
    @State private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
                .environment(\.thumbnails, env.thumbnails)
                .tint(Color.sift.accent)
        }
    }
}
