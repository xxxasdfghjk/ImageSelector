import SwiftUI

@main
struct ImageSelectorApp: App {
    @StateObject private var store = ImageStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // アプリ終了時に展開状態を保存
                    // ContentView の saveSession() が呼ばれるよう通知
                    NotificationCenter.default.post(name: .saveSession, object: nil)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .inactive {
                NotificationCenter.default.post(name: .saveSession, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let saveSession = Notification.Name("saveSession")
}