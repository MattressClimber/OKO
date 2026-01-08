import SwiftUI

struct ContentView: View {
    @StateObject var setupManager = SetupManager()
    
    var body: some View {
        ZStack {
            // Global Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Screen Switcher
            switch setupManager.currentState {
            case .welcome:
                WelcomeView()
            case .modeSelection:
                ModeSelectionView()
            case .scanning:
                ScanningView()
            case .labelInput:       // <--- ADDED THIS CASE
                LabelInputView()
            case .wifiInput:
                WifiInputView()
            case .cameraAlign:
                CameraAlignView()
            case .dashboard:
                DashboardView()
            }
            
            // RED DEV BUTTON (Always on top)
            VStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        setupManager.devSkipForward()
                    }
                }) {
                    Text("DEV: SKIP STEP >>")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.bottom, 20)
            }
        }
        .environmentObject(setupManager) // Inject Brain
        .preferredColorScheme(.dark)
    }
}
