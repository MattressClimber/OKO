import Foundation
import CoreBluetooth
import Combine
import UIKit

// MARK: - BLE Protocol Constants
struct OKOBLEConstants {
    // Service UUID
    static let serviceUUID = CBUUID(string: "4F4B4F00-0001-0001-0001-4F4B4F444556")
    
    // Characteristic UUIDs
    static let wifiListUUID       = CBUUID(string: "4F4B4F01-0001-0001-0001-4F4B4F444556")
    static let wifiCredsUUID      = CBUUID(string: "4F4B4F02-0001-0001-0001-4F4B4F444556")
    static let wifiStatusUUID     = CBUUID(string: "4F4B4F03-0001-0001-0001-4F4B4F444556")
    static let cameraFrameUUID    = CBUUID(string: "4F4B4F04-0001-0001-0001-4F4B4F444556")
    static let cameraCtrlUUID     = CBUUID(string: "4F4B4F05-0001-0001-0001-4F4B4F444556")
    static let roiConfigUUID      = CBUUID(string: "4F4B4F06-0001-0001-0001-4F4B4F444556")
    static let deviceStatusUUID   = CBUUID(string: "4F4B4F07-0001-0001-0001-4F4B4F444556")
    static let deviceConfigUUID   = CBUUID(string: "4F4B4F08-0001-0001-0001-4F4B4F444556")
    static let commandUUID        = CBUUID(string: "4F4B4F09-0001-0001-0001-4F4B4F444556")
}

// MARK: - Data Models

struct WiFiNetwork: Identifiable, Equatable {
    let id = UUID()
    let ssid: String
    let rssi: Int
    let isSecure: Bool
    
    var signalStrength: Int {
        // Convert RSSI to 0-3 bars
        switch rssi {
        case -50...0: return 3
        case -65 ..< -50: return 2
        case -80 ..< -65: return 1
        default: return 0
        }
    }
    
    static func == (lhs: WiFiNetwork, rhs: WiFiNetwork) -> Bool {
        lhs.ssid == rhs.ssid
    }
}

struct DeviceStatus: Codable {
    let label: String?
    let type: String?
    let battery: Int?
    let reading: Int?
    let baselineComplete: Bool?
    let baselineDays: Int?
    let wifiConfigured: Bool?
    let roiConfigured: Bool?
    let photos: Int?
    let boots: Int?
    let version: String?
}

enum WiFiConnectionStatus {
    case disconnected
    case connecting
    case connected(ip: String)
    case failed(error: String)
}

// MARK: - BluetoothManager

class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isBluetoothPoweredOn: Bool = false
    @Published var isScanning: Bool = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isConnected: Bool = false
    @Published var isReady: Bool = false  // All characteristics discovered
    
    // Data from device
    @Published var wifiNetworks: [WiFiNetwork] = []
    @Published var wifiStatus: WiFiConnectionStatus = .disconnected
    @Published var deviceStatus: DeviceStatus?
    @Published var currentFrame: UIImage?
    @Published var isStreaming: Bool = false
    
    // MARK: - Private Properties
    var centralManager: CBCentralManager?
    var connectedPeripheral: CBPeripheral?
    
    // Characteristic references
    private var wifiListChar: CBCharacteristic?
    private var wifiCredsChar: CBCharacteristic?
    private var wifiStatusChar: CBCharacteristic?
    private var cameraFrameChar: CBCharacteristic?
    private var cameraCtrlChar: CBCharacteristic?
    private var roiConfigChar: CBCharacteristic?
    private var deviceStatusChar: CBCharacteristic?
    private var deviceConfigChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    
    // Frame assembly
    private var frameBuffer: Data = Data()
    private var expectedFrameSize: Int = 0
    private var expectedPackets: Int = 0
    private var receivedPackets: Set<Int> = []
    
    private let targetNamePrefix = "Oko"
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        // Initialize CBCentralManager immediately so it's ready when we need it
        // This also triggers the Bluetooth permission prompt early
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        // Initialize central manager if needed
        if centralManager == nil {
            print("🔧 Initializing Bluetooth manager...")
            centralManager = CBCentralManager(delegate: self, queue: nil)
            // Scanning will start automatically in centralManagerDidUpdateState
            return
        }
        
        guard centralManager?.state == .poweredOn else {
            print("❌ Bluetooth not ready, state: \(centralManager?.state.rawValue ?? -1)")
            return
        }
        
        // Don't clear devices if we already have some and are already scanning
        if isScanning {
            print("🔍 Already scanning...")
            return
        }
        
        print("🔍 Starting scan for OKO devices...")
        discoveredDevices.removeAll()
        isScanning = true
        
        // Scan for ALL devices first (more reliable for finding ESP32)
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // After 1 second, also try with specific service UUID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.isScanning else { return }
            print("🔍 Also scanning for specific OKO service...")
            self.centralManager?.scanForPeripherals(
                withServices: [OKOBLEConstants.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }
    
    func stopScanning() {
        guard isScanning else { return }
        centralManager?.stopScan()
        isScanning = false
        print("🛑 Stopped scanning")
    }
    
    /// Restart scanning (clears discovered devices)
    func restartScanning() {
        stopScanning()
        discoveredDevices.removeAll()
        startScanning()
    }
    
    // MARK: - Connection
    
    func connect(to device: CBPeripheral) {
        stopScanning()
        connectedPeripheral = device
        print("🔗 Connecting to \(device.name ?? "Unknown")...")
        centralManager?.connect(device, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        
        // Stop streaming first
        if isStreaming {
            stopCameraStream()
        }
        
        centralManager?.cancelPeripheralConnection(peripheral)
        cleanup()
    }
    
    private func cleanup() {
        wifiListChar = nil
        wifiCredsChar = nil
        wifiStatusChar = nil
        cameraFrameChar = nil
        cameraCtrlChar = nil
        roiConfigChar = nil
        deviceStatusChar = nil
        deviceConfigChar = nil
        commandChar = nil
        
        connectedPeripheral = nil
        isConnected = false
        isReady = false
        isStreaming = false
        
        wifiNetworks = []
        deviceStatus = nil
        currentFrame = nil
    }
    
    // MARK: - Commands
    
    func scanWiFiNetworks() {
        sendCommand("scan_wifi")
    }
    
    func sendWiFiCredentials(ssid: String, password: String) {
        guard let char = wifiCredsChar, let peripheral = connectedPeripheral else {
            print("❌ Cannot send WiFi credentials - not ready")
            return
        }
        
        let credentials = "\(ssid):\(password)"
        guard let data = credentials.data(using: .utf8) else { return }
        
        print("📶 Sending WiFi credentials for: \(ssid)")
        wifiStatus = .connecting
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func sendDeviceConfig(label: String, type: String) {
        guard let char = deviceConfigChar, let peripheral = connectedPeripheral else {
            print("❌ Cannot send device config - not ready")
            return
        }
        
        let config = "\(label):\(type)"
        guard let data = config.data(using: .utf8) else { return }
        
        print("⚙️ Sending device config: \(config)")
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func sendROI(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        guard let char = roiConfigChar, let peripheral = connectedPeripheral else {
            print("❌ Cannot send ROI - not ready")
            return
        }
        
        let roi = String(format: "%.4f,%.4f,%.4f,%.4f", x, y, w, h)
        guard let data = roi.data(using: .utf8) else { return }
        
        print("🎯 Sending ROI: \(roi)")
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func sendDualROI(dialX: CGFloat, dialY: CGFloat, dialW: CGFloat, dialH: CGFloat,
                     spinnerX: CGFloat, spinnerY: CGFloat, spinnerW: CGFloat, spinnerH: CGFloat) {
        guard let char = roiConfigChar, let peripheral = connectedPeripheral else {
            print("❌ Cannot send ROI - not ready")
            return
        }
        
        // Format: "dial:x,y,w,h;spinner:x,y,w,h"
        let roi = String(format: "dial:%.4f,%.4f,%.4f,%.4f;spinner:%.4f,%.4f,%.4f,%.4f",
                         dialX, dialY, dialW, dialH,
                         spinnerX, spinnerY, spinnerW, spinnerH)
        guard let data = roi.data(using: .utf8) else { return }
        
        print("🎯 Sending dual ROI: \(roi)")
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func startCameraStream() {
        guard let char = cameraCtrlChar, let peripheral = connectedPeripheral else {
            print("❌ Cannot start stream - not ready")
            return
        }
        
        guard let data = "start_stream".data(using: .utf8) else { return }
        
        print("📹 Starting camera stream")
        isStreaming = true
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func stopCameraStream() {
        guard let char = cameraCtrlChar, let peripheral = connectedPeripheral else { return }
        guard let data = "stop_stream".data(using: .utf8) else { return }
        
        print("📹 Stopping camera stream")
        isStreaming = false
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func capturePhoto() {
        guard let char = cameraCtrlChar, let peripheral = connectedPeripheral else { return }
        guard let data = "capture".data(using: .utf8) else { return }
        
        print("📸 Requesting photo capture")
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func setFlash(on: Bool) {
        guard let char = cameraCtrlChar, let peripheral = connectedPeripheral else { return }
        let command = on ? "flash_on" : "flash_off"
        guard let data = command.data(using: .utf8) else { return }
        
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func requestStatus() {
        sendCommand("get_status")
    }
    
    func resetDevice() {
        sendCommand("reset")
    }
    
    private func sendCommand(_ command: String) {
        guard let char = commandChar, let peripheral = connectedPeripheral else {
            print("❌ Cannot send command - not ready")
            return
        }
        
        guard let data = command.data(using: .utf8) else { return }
        
        print("🔧 Sending command: \(command)")
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.isBluetoothPoweredOn = (central.state == .poweredOn)
        }
        
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth is ON")
            // Auto-start scanning when Bluetooth becomes ready
            if !isScanning {
                startScanning()
            }
        case .poweredOff:
            print("❌ Bluetooth is OFF")
            isScanning = false
        case .unauthorized:
            print("❌ Bluetooth unauthorized")
        case .unsupported:
            print("❌ Bluetooth unsupported")
        default:
            print("⏳ Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any],
                       rssi RSSI: NSNumber) {
        
        // Filter by name prefix
        guard let name = peripheral.name,
              name.localizedCaseInsensitiveContains(targetNamePrefix) else {
            return
        }
        
        // Avoid duplicates
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            print("🔎 Discovered: \(name) (RSSI: \(RSSI))")
            DispatchQueue.main.async {
                self.discoveredDevices.append(peripheral)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        print("🎉 Connected to \(peripheral.name ?? "Device")")
        
        DispatchQueue.main.async {
            self.isConnected = true
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([OKOBLEConstants.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown")")
        cleanup()
    }
    
    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("🔌 Disconnected from \(peripheral.name ?? "Device")")
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Service discovery error: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("📦 Found service: \(service.uuid)")
            if service.uuid == OKOBLEConstants.serviceUUID {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        if let error = error {
            print("❌ Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            print("  📝 Found characteristic: \(char.uuid)")
            
            switch char.uuid {
            case OKOBLEConstants.wifiListUUID:
                wifiListChar = char
                peripheral.setNotifyValue(true, for: char)
                
            case OKOBLEConstants.wifiCredsUUID:
                wifiCredsChar = char
                
            case OKOBLEConstants.wifiStatusUUID:
                wifiStatusChar = char
                peripheral.setNotifyValue(true, for: char)
                
            case OKOBLEConstants.cameraFrameUUID:
                cameraFrameChar = char
                peripheral.setNotifyValue(true, for: char)
                
            case OKOBLEConstants.cameraCtrlUUID:
                cameraCtrlChar = char
                
            case OKOBLEConstants.roiConfigUUID:
                roiConfigChar = char
                
            case OKOBLEConstants.deviceStatusUUID:
                deviceStatusChar = char
                peripheral.setNotifyValue(true, for: char)
                
            case OKOBLEConstants.deviceConfigUUID:
                deviceConfigChar = char
                
            case OKOBLEConstants.commandUUID:
                commandChar = char
                
            default:
                break
            }
        }
        
        // Check if we have all required characteristics
        let ready = wifiListChar != nil &&
                    wifiCredsChar != nil &&
                    cameraCtrlChar != nil &&
                    roiConfigChar != nil &&
                    deviceStatusChar != nil &&
                    commandChar != nil
        
        DispatchQueue.main.async {
            self.isReady = ready
            if ready {
                print("✅ All characteristics discovered - device ready")
                // Automatically request initial status and WiFi scan
                self.requestStatus()
                self.scanWiFiNetworks()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("❌ Update error: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case OKOBLEConstants.wifiListUUID:
            handleWiFiList(data: data)
            
        case OKOBLEConstants.wifiStatusUUID:
            handleWiFiStatus(data: data)
            
        case OKOBLEConstants.cameraFrameUUID:
            handleCameraFrame(data: data)
            
        case OKOBLEConstants.deviceStatusUUID:
            handleDeviceStatus(data: data)
            
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("❌ Write error for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            print("✅ Write successful for \(characteristic.uuid)")
        }
    }
}

// MARK: - Data Handlers

extension BluetoothManager {
    
    private func handleWiFiList(data: Data) {
        print("📶 handleWiFiList called with \(data.count) bytes")
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            print("❌ Could not decode data as UTF-8 string")
            return
        }
        print("📶 Received WiFi list JSON: \(jsonString)")
        
        // Parse JSON array of networks
        guard let jsonData = jsonString.data(using: .utf8),
              let networks = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            print("❌ Failed to parse WiFi list JSON")
            return
        }
        
        let parsedNetworks = networks.compactMap { dict -> WiFiNetwork? in
            guard let ssid = dict["ssid"] as? String,
                  let rssi = dict["rssi"] as? Int else { 
                print("❌ Missing ssid or rssi in network dict: \(dict)")
                return nil 
            }
            let secure = dict["secure"] as? Bool ?? true
            print("✅ Parsed network: \(ssid) (\(rssi)dBm)")
            return WiFiNetwork(ssid: ssid, rssi: rssi, isSecure: secure)
        }.sorted { $0.rssi > $1.rssi }
        
        print("📶 Total parsed networks: \(parsedNetworks.count)")
        
        DispatchQueue.main.async {
            self.wifiNetworks = parsedNetworks
            print("📶 Updated wifiNetworks array, count: \(self.wifiNetworks.count)")
        }
    }
    
    private func handleWiFiStatus(data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8) else { 
            print("❌ WiFi status: Could not decode as UTF-8")
            return 
        }
        print("📶 WiFi status received: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ WiFi status: Could not parse JSON")
            return
        }
        
        print("📶 WiFi status parsed: \(dict)")
        
        DispatchQueue.main.async {
            // Check for new "status" field format
            if let status = dict["status"] as? String {
                switch status {
                case "connecting":
                    print("📶 WiFi connecting...")
                    self.wifiStatus = .connecting
                    
                case "connected":
                    let ip = dict["ip"] as? String ?? "connected"
                    print("✅ WiFi connected with IP: \(ip)")
                    self.wifiStatus = .connected(ip: ip)
                    
                case "failed":
                    let error = dict["error"] as? String ?? "Connection failed"
                    print("❌ WiFi failed: \(error)")
                    self.wifiStatus = .failed(error: error)
                    
                default:
                    print("⚠️ Unknown WiFi status: \(status)")
                }
                return
            }
            
            // Legacy format fallback
            if let saved = dict["saved"] as? Bool, saved == true {
                print("✅ WiFi credentials saved on device - advancing to camera")
                self.wifiStatus = .connected(ip: "saved")
                return
            }
            
            if let connected = dict["connected"] as? Bool {
                if connected, let ip = dict["ip"] as? String {
                    print("✅ WiFi connected with IP: \(ip)")
                    self.wifiStatus = .connected(ip: ip)
                } else if let error = dict["error"] as? String {
                    print("❌ WiFi error: \(error)")
                    self.wifiStatus = .failed(error: error)
                } else {
                    self.wifiStatus = .disconnected
                }
            }
        }
    }
    
    private func handleCameraFrame(data: Data) {
        // Try to parse as string first (for header/end markers)
        if let str = String(data: data, encoding: .utf8) {
            print("📷 Frame control message: '\(str)'")
            
            if str.hasPrefix("FRAME:") {
                // Header: "FRAME:totalPackets:totalSize"
                let parts = str.split(separator: ":")
                if parts.count == 3,
                   let packets = Int(parts[1]),
                   let size = Int(parts[2]) {
                    print("📷 Starting frame: \(packets) packets, \(size) bytes")
                    frameBuffer = Data()
                    frameBuffer.reserveCapacity(size)
                    expectedPackets = packets
                    expectedFrameSize = size
                    receivedPackets.removeAll()
                }
                return
            } else if str == "FRAME_END" {
                // Frame complete
                print("📷 Frame END received")
                assembleFrame()
                return
            }
        }
        
        // Binary data - frame chunk
        print("📷 Received chunk: \(data.count) bytes")
        processFrameChunk(data: data)
    }
    
    private func processFrameChunk(data: Data) {
        guard data.count > 2 else { return }
        
        // First 2 bytes are packet number
        let packetNum = Int(data[0]) << 8 | Int(data[1])
        let chunkData = data.subdata(in: 2..<data.count)
        
        // For simplicity, just append (proper implementation would handle out-of-order)
        frameBuffer.append(chunkData)
        receivedPackets.insert(packetNum)
    }
    
    private func assembleFrame() {
        guard frameBuffer.count > 0 else {
            print("❌ Empty frame buffer")
            return
        }
        
        print("📷 Assembling frame: \(frameBuffer.count) bytes (\(receivedPackets.count)/\(expectedPackets) packets)")
        
        // Try to decode JPEG
        if let image = UIImage(data: frameBuffer) {
            DispatchQueue.main.async {
                self.currentFrame = image
            }
            print("✅ Frame decoded successfully")
        } else {
            print("❌ Failed to decode frame as JPEG")
        }
        
        // Reset for next frame
        frameBuffer = Data()
        expectedPackets = 0
        expectedFrameSize = 0
        receivedPackets.removeAll()
    }
    
    private func handleDeviceStatus(data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8) else { return }
        print("📊 Device status: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8) else { return }
        
        do {
            let status = try JSONDecoder().decode(DeviceStatus.self, from: jsonData)
            DispatchQueue.main.async {
                self.deviceStatus = status
            }
        } catch {
            print("❌ Failed to decode device status: \(error)")
        }
    }
}
