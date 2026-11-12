import SwiftUI

/// Plazvo Player para iPhone e iPad.
@main
struct PlazvoPlayerApp: App {
    @StateObject private var model = AppModel(AppEnvironment.make())

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
