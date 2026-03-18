import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: ImageStore

    var body: some View {
        NavigationSplitView {
            SidebarView().environmentObject(store)
        } detail: {
            if let group = store.selectedGroup {
                ImageGridView(group: group)
            } else {
                Text("フォルダを選択してください")
            }
        }
        .toolbar {
            Button("フォルダ選択") {
                selectFolder()
            }
        }
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                store.loadFolder(url: url)
            }
        }
    }
}
