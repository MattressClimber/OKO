import SwiftUI
import Combine
import CoreBluetooth

// MARK: - DATA MODELS

/// Represents a single OKO device
struct OkoDevice: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var type: String       // "Water" or "Gauge"
    var installDate: Date
    var lastReading: String
    var status: DeviceStatus
    var batteryPercent: Int
    var peripheralIdentifier: String?  // BLE identifier for reconnection
    
    enum DeviceStatus: String, Codable {
        case learning
        case ok
        case leakDetected
        case offline
    }
    
    static func == (lhs: OkoDevice, rhs: OkoDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// The steps of the setup flow
enum SetupState {
    case welcome
    case modeSelection
    case scanning
    case labelInput
    case wifiInput
    case cameraAlign
    case dashboard
}

// MARK: - THE MANAGER

class SetupManager: ObservableObject {
    @Published var currentState: SetupState = .welcome
    
    // THE BLE ENGINE
    @Published var bleManager = BluetoothManager()
    private var cancellables = Set<AnyCancellable>()
    
    // SETUP FLOW TEMP DATA
    @Published var tempSelectedMode: String = "Water"
    @Published var tempDeviceLabel: String = ""
    @Published var selectedWiFiNetwork: WiFiNetwork?
    @Published var wifiPassword: String = ""
    
    // WiFi connection state
    @Published var isConnectingToWiFi: Bool = false
    @Published var wifiConnectionError: String?
    
    // FLEET MANAGEMENT
    @Published var devices: [OkoDevice] = []
    @Published var currentDeviceIndex: Int = 0
    
    /// Helper to get the active device safely
    var activeDevice: OkoDevice? {
        if devices.indices.contains(currentDeviceIndex) {
            return devices[currentDeviceIndex]
        }
        return nil
    }
    
    // MARK: - Initialization

    init() {
        loadDevices()
        
        if !devices.isEmpty {
            print("💾 Saved devices found. Jumping to Dashboard.")
            currentState = .dashboard
        } else {
            currentState = .welcome
        }
        
        setupBluetoothBindings()
    }
    
    // MARK: - BLUETOOTH BINDINGS
    
    private func setupBluetoothBindings() {
        // When BLE connects, move to label input
        bleManager.$isConnected
            .filter { $0 == true }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Only advance if we're in scanning state
                if self.currentState == .scanning {
                    print("✅ Connected! Moving to Label Input.")
                    self.advanceFromScanning()
                }
            }
            .store(in: &cancellables)
        
        // When device is ready (all characteristics discovered), request WiFi scan
        bleManager.$isReady
            .filter { $0 == true }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("🔵 Device ready - WiFi networks will be scanned automatically")
            }
            .store(in: &cancellables)
        
        // Monitor WiFi connection status
        bleManager.$wifiStatus
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
                    print("✅ WiFi connected with IP: \(ip)")
                    // Auto-advance to camera alignment
                    if self.currentState == .wifiInput {
                        withAnimation { self.currentState = .cameraAlign }
                    }
                    
                case .failed(let error):
                    self.isConnectingToWiFi = false
                    self.wifiConnectionError = error
                    print("❌ WiFi connection failed: \(error)")
                    
                case .disconnected:
                    self.isConnectingToWiFi = false
                }
            }
            .store(in: &cancellables)
        
        // Update device status when received
        bleManager.$deviceStatus
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateActiveDeviceFromStatus(status)
            }
            .store(in: &cancellables)
    }
    
    private func updateActiveDeviceFromStatus(_ status: DeviceStatus) {
        guard var device = activeDevice,
              let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        
        if let battery = status.battery {
            device.batteryPercent = battery
        }
        if let reading = status.reading {
            device.lastReading = "\(reading) L"
        }
        if let baselineComplete = status.baselineComplete {
            device.status = baselineComplete ? .ok : .learning
        }
        
        devices[index] = device
        saveDevices()
    }
    
    // MARK: - ACTIONS
    
    func startNewSetup() {
        // Reset temp variables
        tempSelectedMode = "Water"
        tempDeviceLabel = ""
        selectedWiFiNetwork = nil
        wifiPassword = ""
        wifiConnectionError = nil
        isConnectingToWiFi = false
        
        // Reset Bluetooth
        bleManager.disconnect()
        bleManager.discoveredDevices.removeAll()
        
        currentState = .welcome
    }
    
    func selectMode(_ mode: String) {
        tempSelectedMode = mode
        withAnimation { currentState = .scanning }
        
        print("🔍 Starting scan for \(mode) devices...")
        bleManager.startScanning()
    }
    
    /// Called when user taps a device in the list
    func userDidSelectDevice(_ device: CBPeripheral) {
        print("👆 User selected: \(device.name ?? "Unknown")")
        bleManager.connect(to: device)
    }
    
    private func advanceFromScanning() {
        withAnimation { currentState = .labelInput }
    }
    
    func submitLabel() {
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Send device config to ESP32
        bleManager.sendDeviceConfig(label: tempDeviceLabel, type: tempSelectedMode)
        
        // The WiFi networks should already be loaded from automatic scan
        withAnimation { currentState = .wifiInput }
    }
    
    func connectToSelectedWiFi() {
        guard let network = selectedWiFiNetwork else {
            print("❌ No network selected")
            return
        }
        
        print("📶 Connecting to \(network.ssid)...")
        bleManager.sendWiFiCredentials(ssid: network.ssid, password: wifiPassword)
    }
    
    func refreshWiFiNetworks() {
        bleManager.scanWiFiNetworks()
    }
    
    func completeSetup() {
        // Send ROI to device (will be called from CameraAlignView)
        
        // Create the new device entry
        let newDevice = OkoDevice(
            name: tempDeviceLabel.isEmpty ? "New OKO" : tempDeviceLabel,
            type: tempSelectedMode,
            installDate: Date(),
            lastReading: "---",
            status: .learning,
            batteryPercent: bleManager.deviceStatus?.battery ?? 100,
            peripheralIdentifier: bleManager.connectedPeripheral?.identifier.uuidString
        )
        
        devices.append(newDevice)
        currentDeviceIndex = devices.count - 1
        
        saveDevices()
        
        // Disconnect BLE (device will go to sleep)
        bleManager.disconnect()
        
        withAnimation { currentState = .dashboard }
    }
    
    func deleteDevice(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        saveDevices()
        
        if devices.isEmpty {
            currentState = .welcome
        } else {
            currentDeviceIndex = 0
        }
    }
    
    // MARK: - ROI Handling
    
    func saveROI(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        print("🎯 Saving ROI: x=\(x), y=\(y), w=\(w), h=\(h)")
        
        // Send to ESP32
        bleManager.sendROI(x: x, y: y, w: w, h: h)
        
        // Small delay to ensure it's sent before completing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.completeSetup()
        }
    }
    
    func saveROIs(dialX: CGFloat, dialY: CGFloat, dialW: CGFloat, dialH: CGFloat,
                  spinnerX: CGFloat, spinnerY: CGFloat, spinnerW: CGFloat, spinnerH: CGFloat) {
        print("🎯 Saving Dial ROI: x=\(dialX), y=\(dialY), w=\(dialW), h=\(dialH)")
        print("🎯 Saving Spinner ROI: x=\(spinnerX), y=\(spinnerY), w=\(spinnerW), h=\(spinnerH)")
        
        // Send both ROIs to ESP32
        bleManager.sendDualROI(
            dialX: dialX, dialY: dialY, dialW: dialW, dialH: dialH,
            spinnerX: spinnerX, spinnerY: spinnerY, spinnerW: spinnerW, spinnerH: spinnerH
        )
        
        // Small delay to ensure it's sent before completing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.completeSetup()
        }
    }
    
    // MARK: - Camera Stream Control
    
    func startCameraStream() {
        bleManager.startCameraStream()
    }
    
    func stopCameraStream() {
        bleManager.stopCameraStream()
    }
    
    // MARK: - DATA PERSISTENCE
    
    private func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "SavedOkoDevices")
            print("💾 Devices saved.")
        }
    }
    
    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: "SavedOkoDevices"),
           let decoded = try? JSONDecoder().decode([OkoDevice].self, from: data) {
            self.devices = decoded
        }
    }
    
    // MARK: - NAVIGATION HELPERS
    
    func devSkipForward() {
        if currentState == .scanning {
            bleManager.stopScanning()
        }
        
        switch currentState {
        case .welcome: currentState = .modeSelection
        case .modeSelection: selectMode(tempSelectedMode)
        case .scanning: currentState = .labelInput
        case .labelInput: currentState = .wifiInput
        case .wifiInput: currentState = .cameraAlign
        case .cameraAlign: completeSetup()
        case .dashboard: currentState = .welcome
        }
    }
    
    func goBack() {
        switch currentState {
        case .modeSelection:
            currentState = .welcome
            
        case .scanning:
            bleManager.stopScanning()
            bleManager.disconnect()
            currentState = .modeSelection
            
        case .labelInput:
            currentState = .scanning
            
        case .wifiInput:
            currentState = .labelInput
            
        case .cameraAlign:
            stopCameraStream()
            currentState = .wifiInput
            
        default:
            break
        }
    }
}
