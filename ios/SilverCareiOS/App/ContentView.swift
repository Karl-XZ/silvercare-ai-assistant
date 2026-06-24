import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: SilverCareAppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
                .ignoresSafeArea()

            NativeCameraPreview(cameraService: appModel.cameraService)
                .opacity(appModel.cameraPreviewVisible ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            SilverCareWebView(appModel: appModel)
                .ignoresSafeArea()

            if appModel.automationEnabled {
                Text(appModel.automationSnapshot)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("SilverCareAutomationState")
                    .accessibilityLabel(appModel.automationSnapshot)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if appModel.automationEnabled {
                appModel.prepareForAutomation()
                await appModel.runAutomationLocalBenchmarksIfRequested()
            } else {
                await appModel.requestStartupPermissions()
            }
        }
    }
}
