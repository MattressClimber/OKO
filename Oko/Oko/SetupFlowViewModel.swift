import SwiftUI
import Combine
import CoreBluetooth

// MARK: - Setup Flow ViewModel

@MainActor
final class SetupFlowViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentState: SetupState = .welcome
    
    // Setup flow data
    @Published var selectedMode: OkoDevice.DeviceType = .water
    @Published var deviceLabel = ""
    @Published var selectedWiFiNetwork: WiFiNetwork?
    @Published var wifiPassword = ""
    
    // WiFi state
    @Published var isConnectingToWiFi = false
    @Published var wifiConnectionError: String?
    @Published var isRefreshingWiFi = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private weak var bluetoothService: BluetoothService?
    private weak var cameraService: CameraService?
    private weak var persistenceService: PersistenceService?
    
    // MARK: - Setup
    
    func setup(
        bluetoothService: BluetoothService,
        cameraService: CameraService,
        persistenceService: PersistenceService
    ) {
        self.bluetoothService = bluetoothService
        self.cameraService = cameraService
        self.persistenceService = persistenceService
        
        setupBindings()
    }
    
    private func setupBindings() {
        guard let bluetoothService = bluetoothService else { return }
        
        bluetoothService.$isConnected
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.currentState == .scanning else { return }
                withAnimation { self.currentState = .labelInput }
            }
            .store(in: &cancellables)
        
        bluetoothService.$wifiNetworks
            .receive(on: RunLoop.main)
            .sink { [weak self] networks in
                if !networks.isEmpty {
                    self?.isRefreshingWiFi = false
                }
            }
            .store(in: &cancellables)
        
        bluetoothService.$wifiStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                
                switch status {
                case .connecting:
                    self.isConnectingToWiFi = true
                    self.wifiConnectionError = nil
                    
                case .connected(let ip):
                    self.isConnectingToWiFi = false
                    self.wifiConnectionError = nil
                    
                    // Automatically advance to camera view when WiFi is connected
                    if self.currentState == .wifiInput {
                        print("✅ WiFi connected with IP: \(ip) - advancing to camera setup")
                        
                        // Short delay to let the connection stabilize
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            withAnimation { 
                                self.currentState = .cameraAlign
                            }
                        }
                    }
                    
                case .failed(let error):
                    self.isConnectingToWiFi = false
                    self.wifiConnectionError = error
                    
                case .disconnected:
                    self.isConnectingToWiFi = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func startNewSetup() {
        selectedMode = .water
        deviceLabel = ""
        selectedWiFiNetwork = nil
        wifiPassword = ""
        wifiConnectionError = nil
        isConnectingToWiFi = false
        isRefreshingWiFi = false
        
        bluetoothService?.disconnect()
        
        currentState = .welcome
    }
    
    func selectMode(_ mode: OkoDevice.DeviceType) {
        selectedMode = mode
        withAnimation { currentState = .scanning }
        bluetoothService?.startScanning()
    }
    
    func connectToDevice(_ peripheral: CBPeripheral) {
        bluetoothService?.connect(to: peripheral)
    }
    
    func submitLabel() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        bluetoothService?.sendDeviceConfig(label: deviceLabel, type: selectedMode.rawValue)
        withAnimation { currentState = .wifiInput }
    }
    
    func connectToSelectedWiFi() {
        guard let network = selectedWiFiNetwork else { return }
        bluetoothService?.sendWiFiCredentials(ssid: network.ssid, password: wifiPassword)
    }
    
    func skipWiFi() {
        withAnimation { currentState = .cameraAlign }
    }
    
    func refreshWiFiNetworks() {
        isRefreshingWiFi = true
        bluetoothService?.clearWiFiNetworks()
        bluetoothService?.scanWiFiNetworks()
        
        Task {
            try? await Task.sleep(for: .seconds(5))
            isRefreshingWiFi = false
        }
    }
    
    func saveROIs(
        dialX: CGFloat, dialY: CGFloat, dialW: CGFloat, dialH: CGFloat,
        spinnerX: CGFloat, spinnerY: CGFloat, spinnerW: CGFloat, spinnerH: CGFloat
    ) {
        bluetoothService?.sendDualROI(
            dialX: dialX, dialY: dialY, dialW: dialW, dialH: dialH,
            spinnerX: spinnerX, spinnerY: spinnerY, spinnerW: spinnerW, spinnerH: spinnerH
        )
        
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            completeSetup()
        }
    }
    
    func completeSetup() {
        let newDevice = OkoDevice(
            name: deviceLabel.isEmpty ? "New OKO" : deviceLabel,
            type: selectedMode,
            installDate: Date(),
            lastReading: "---",
            status: .learning,
            batteryPercent: bluetoothService?.deviceStatus?.battery ?? 100,
            peripheralIdentifier: bluetoothService?.connectedPeripheral?.identifier.uuidString
        )
        
        persistenceService?.saveDevice(newDevice)
        bluetoothService?.disconnect()
        
        withAnimation { currentState = .dashboard }
    }
    
    // MARK: - Navigation
    
    func goBack() {
        switch currentState {
        case .modeSelection:
            currentState = .welcome
        case .scanning:
            bluetoothService?.stopScanning()
            bluetoothService?.disconnect()
            currentState = .modeSelection
        case .labelInput:
            currentState = .scanning
        case .wifiInput:
            currentState = .labelInput
        case .cameraAlign:
            cameraService?.stopCameraStream()
            currentState = .wifiInput
        default:
            break
        }
    }
    
    func devSkipForward() {
        switch currentState {
        case .welcome: currentState = .modeSelection
        case .modeSelection: selectMode(selectedMode)
        case .scanning: currentState = .labelInput
        case .labelInput: currentState = .wifiInput
        case .wifiInput: currentState = .cameraAlign
        case .cameraAlign: completeSetup()
        case .dashboard: currentState = .welcome
        }
    }
}
