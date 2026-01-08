import SwiftUI

@main
struct OkoApp: App {
    // 1. Listen for the setting at the global level
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 2. FORCE the whole app to respect the setting
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
