
import SwiftUI

// MARK: - App Coordinator

struct AppCoordinator: View {
    @EnvironmentObject var persistenceService: PersistenceService
    @EnvironmentObject var bluetoothService: BluetoothService
    @EnvironmentObject var cameraService: CameraService
    
    @StateObject private var setupViewModel = SetupFlowViewModel()
    
    var body: some View {
        ZStack {
            Color("BackgroundTheme")
                .ignoresSafeArea()
            
            Group {
                if persistenceService.devices.isEmpty && setupViewModel.currentState == .welcome {
                    // First time - show setup
                    SetupFlowView()
                } else if setupViewModel.currentState != .welcome && setupViewModel.currentState != .dashboard {
                    // In setup flow
                    SetupFlowView()
                } else {
                    // Dashboard
                    DashboardView()
                }
            }
            .environmentObject(setupViewModel)
        }
        .animation(.easeInOut(duration: 0.3), value: setupViewModel.currentState)
        .onAppear {
            setupViewModel.setup(
                bluetoothService: bluetoothService,
                cameraService: cameraService,
                persistenceService: persistenceService
            )
        }
    }
}

// MARK: - Setup Flow View

private struct SetupFlowView: View {
    @EnvironmentObject var setupViewModel: SetupFlowViewModel
    
    var body: some View {
        switch setupViewModel.currentState {
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
            EmptyView()
        }
    }
}
