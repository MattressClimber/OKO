import SwiftUI
import Combine
import CoreBluetooth

// MARK: - DATA MODELS

// 1. The definition for a single Oko unit (Codable for saving)
struct OkoDevice: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var type: String       // "Water" or "Gauge"
    var installDate: Date
    var lastReading: String
    var status: DeviceStatus
    
    enum DeviceStatus: String, Codable {
        case learning
        case ok
        case leakDetected
        case offline
    }
}

// 2. The steps of the setup flow
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
    
    // THE ENGINE
    @Published var bleManager = BluetoothManager()
    private var cancellables = Set<AnyCancellable>()
    
    // SETUP FLOW TEMP DATA
    @Published var tempSelectedMode: String = "Water"
    @Published var tempDeviceLabel: String = ""
    @Published var foundNetworks: [(String, Bool)] = [] // Stores Wi-Fi list from ESP32
    
    // FLEET MANAGEMENT (Holds all your devices)
    @Published var devices: [OkoDevice] = []
    @Published var currentDeviceIndex: Int = 0
    
    // Helper to get the active device safely
    var activeDevice: OkoDevice? {
        if devices.indices.contains(currentDeviceIndex) {
            return devices[currentDeviceIndex]
        }
        return nil
    }

    init() {
        // 1. Load saved data on launch
        loadDevices()
        
        // 2. Set the initial view
        if !devices.isEmpty {
            print("💾 Saved devices found. Jumping to Dashboard.")
            currentState = .dashboard
        } else {
            currentState = .welcome
        }
        
        // 3. Setup Bluetooth Observers
        setupBluetoothBindings()
    }
    
    // MARK: - BLUETOOTH BINDINGS
    
    private func setupBluetoothBindings() {
        // NOTE: We removed the "Auto-Connect" logic here.
        // We now wait for the USER to select a device in ScanningView.
        
        // Observer: When connected, move to next screen automatically
        bleManager.$isConnected
            .filter { $0 == true } // Only when true
            .receive(on: RunLoop.main) // Ensure UI updates on main thread
            .sink { [weak self] _ in
                print("✅ Connected! Moving to Label Input.")
                self?.advanceFromScanning()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - ACTIONS
    
    func startNewSetup() {
            // Reset temp variables
            tempSelectedMode = "Water"
            tempDeviceLabel = ""
            foundNetworks = []
            
            // Reset Bluetooth scanning
            bleManager.stopScanning()
            
            // FIX: 'foundDevice' no longer exists. We clear the connected one instead.
            bleManager.connectedPeripheral = nil
            
            bleManager.discoveredDevices.removeAll()
            bleManager.isConnected = false
            
            currentState = .welcome
        }
    func selectMode(_ mode: String) {
        self.tempSelectedMode = mode
        withAnimation { currentState = .scanning }
        
        // Trigger scanning only after mode selection
        print("🔍 Starting Scan for \(mode)...")
        bleManager.startScanning()
    }
    
    // Called when user taps a device in the list (ScanningView)
    func userDidSelectDevice(_ device: CBPeripheral) {
        print("👆 User selected: \(device.name ?? "Unknown")")
        bleManager.connect(to: device)
    }
    
    private func advanceFromScanning() {
        // Give a tiny delay for UX transition?
        withAnimation { currentState = .labelInput }
    }
    
    func submitLabel() {
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // TEST DATA: Populate fake Wi-Fi networks so the next screen isn't empty
        // (Remove this once we have real data parsing from ESP32)
        self.foundNetworks = [("Home_WiFi_5G", true), ("Guest_Network", false), ("Office", true)]
        
        withAnimation { currentState = .wifiInput }
    }
    
    func completeSetup() {
        // Create the new device
        let newDevice = OkoDevice(
            name: tempDeviceLabel.isEmpty ? "New OKO" : tempDeviceLabel, // Using updated branding
            type: tempSelectedMode,
            installDate: Date(), // Timestamp: Now
            lastReading: "---",
            status: .learning
        )
        
        devices.append(newDevice)
        currentDeviceIndex = devices.count - 1 // Switch to new device
        
        // Save Changes
        saveDevices()
        
        withAnimation { currentState = .dashboard }
    }
    
    func deleteDevice(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        saveDevices()
        
        // Safety check: if empty, go to welcome
        if devices.isEmpty {
            currentState = .welcome
        } else {
            currentDeviceIndex = 0
        }
    }
    
    // MARK: - DATA PERSISTENCE
    
    private func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "SavedOkoDevices")
            print("💾 Devices saved.")
        }
    }
    
    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: "SavedOkoDevices") {
            if let decoded = try? JSONDecoder().decode([OkoDevice].self, from: data) {
                self.devices = decoded
            }
        }
    }
    
    // MARK: - NAVIGATION HELPERS
    
    func devSkipForward() {
        // Stop scanning if we are forcibly skipping
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
        case .modeSelection: currentState = .welcome
        case .scanning:
            bleManager.stopScanning()
            currentState = .modeSelection
        case .labelInput: currentState = .scanning
        case .wifiInput: currentState = .labelInput
        case .cameraAlign: currentState = .wifiInput
        default: break
        }
    }
    
    // New function to save the "Region of Interest" (ROI)
    func saveROI(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let roiData = [
            "x": Float(x),
            "y": Float(y),
            "w": Float(w),
            "h": Float(h)
        ]
        
        print("Calculated ROI for ESP32: \(roiData)")
        
        // TODO: Send this to ESP32 via BLE
        // bleManager.sendJSON("set_roi", data: roiData)
        
        // Finish Setup
        completeSetup()
    }
}
