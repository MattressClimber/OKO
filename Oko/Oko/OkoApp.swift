import SwiftUI

@main
struct OkoApp: App {
    // Global dark mode setting - synced with all views using @AppStorage
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
