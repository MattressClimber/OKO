import SwiftUI

struct ContentView: View {
    @StateObject private var manager = SetupManager()
    
    var body: some View {
        ZStack {
            // Background
            Color("BackgroundTheme")
                .ignoresSafeArea()
            
            // Main content based on current state
            switch manager.currentState {
            case .welcome:
                WelcomeView()
                
            case .modeSelection:
                ModeSelectionView()
                
            case .scanning:
                ScanningView()
                
            case .labelInput:
                LabelInputView()
                
            case .wifiInput:
                WifiInputView()
                
            case .cameraAlign:
                CameraAlignView()
                
            case .dashboard:
                DashboardView()
            }
        }
        .environmentObject(manager)
        .animation(.easeInOut(duration: 0.3), value: manager.currentState)
    }
}

#Preview {
    ContentView()
}
