import SwiftUI

@main
struct SilverCareiOSApp: App {
    @StateObject private var appModel = SilverCareAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }
}
