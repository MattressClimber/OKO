import SwiftUI

@main
struct OkoApp: App {
    // MARK: - State
    
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    // MARK: - Services
    
    @StateObject private var persistenceService = PersistenceService.shared
    @StateObject private var bluetoothService = BluetoothService()
    @StateObject private var cameraService = CameraService()
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            AppCoordinator()
                .environmentObject(persistenceService)
                .environmentObject(bluetoothService)
                .environmentObject(cameraService)
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .onAppear {
                    cameraService.setupWith(bluetoothService: bluetoothService)
                }
        }
    }
}
