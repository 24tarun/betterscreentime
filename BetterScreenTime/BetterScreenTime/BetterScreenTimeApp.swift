import SwiftUI

@main
struct BetterScreenTimeApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("bridgeSmallGaps") private var bridgeSmallGaps: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Divider()
                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Divider()
                Toggle("Bridge Small Gaps", isOn: $bridgeSmallGaps)
            }
        }
    }
}
