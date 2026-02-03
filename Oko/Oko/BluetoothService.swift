import Foundation
import CoreBluetooth
import Combine

// MARK: - Bluetooth Service

@MainActor
final class BluetoothService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isBluetoothPoweredOn = false
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isConnected = false
    @Published var isReady = false
    
    // Data from device
    @Published var wifiNetworks: [WiFiNetwork] = []
    @Published var wifiStatus: WiFiConnectionStatus = .disconnected
    @Published var deviceStatus: DeviceStatus?
    
    // MARK: - Internal Properties
    
    private(set) var connectedPeripheral: CBPeripheral?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        Task { @MainActor in
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        guard let central = centralManager, central.state == .poweredOn else {
            print("❌ Bluetooth not ready")
            return
        }
        
        guard !isScanning else { return }
        
        print("🔍 Starting scan...")
        discoveredDevices.removeAll()
        isScanning = true
        
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard isScanning else { return }
            central.scanForPeripherals(
                withServices: [BLEConstants.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }
    
    func stopScanning() {
        guard isScanning else { return }
        centralManager?.stopScan()
        isScanning = false
    }
    
    // MARK: - Connection
    
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        centralManager?.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
        cleanup()
    }
    
    private func cleanup() {
        characteristics.removeAll()
        connectedPeripheral = nil
        isConnected = false
        isReady = false
        wifiNetworks = []
        deviceStatus = nil
    }
    
    // MARK: - Commands
    
    func scanWiFiNetworks() {
        sendCommand("scan_wifi")
    }
    
    func clearWiFiNetworks() {
        wifiNetworks.removeAll()
    }
    
    func sendWiFiCredentials(ssid: String, password: String) {
        guard let char = characteristics[BLEConstants.wifiCredsUUID],
              let peripheral = connectedPeripheral else { return }
        
        let credentials = "\(ssid):\(password)"
        guard let data = credentials.data(using: .utf8) else { return }
        
        wifiStatus = .connecting
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func sendDeviceConfig(label: String, type: String) {
        guard let char = characteristics[BLEConstants.deviceConfigUUID],
              let peripheral = connectedPeripheral else { return }
        
        let config = "\(label):\(type)"
        guard let data = config.data(using: .utf8) else { return }
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func sendDualROI(
        dialX: CGFloat, dialY: CGFloat, dialW: CGFloat, dialH: CGFloat,
        spinnerX: CGFloat, spinnerY: CGFloat, spinnerW: CGFloat, spinnerH: CGFloat
    ) {
        guard let char = characteristics[BLEConstants.roiConfigUUID],
              let peripheral = connectedPeripheral else { return }
        
        let roi = String(
            format: "dial:%.4f,%.4f,%.4f,%.4f;spinner:%.4f,%.4f,%.4f,%.4f",
            dialX, dialY, dialW, dialH,
            spinnerX, spinnerY, spinnerW, spinnerH
        )
        guard let data = roi.data(using: .utf8) else { return }
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func requestStatus() {
        sendCommand("get_status")
    }
    
    private func sendCommand(_ command: String) {
        guard let char = characteristics[BLEConstants.commandUUID],
              let peripheral = connectedPeripheral else { return }
        
        guard let data = command.data(using: .utf8) else { return }
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            isBluetoothPoweredOn = (central.state == .poweredOn)
            
            if central.state == .poweredOn && !isScanning {
                startScanning()
            }
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let name = peripheral.name,
              name.localizedCaseInsensitiveContains(BLEConstants.deviceNamePrefix) else {
            return
        }
        
        Task { @MainActor in
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredDevices.append(peripheral)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            isConnected = true
            peripheral.delegate = self
            peripheral.discoverServices([BLEConstants.serviceUUID])
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            cleanup()
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BLEConstants.serviceUUID {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        
        Task { @MainActor in
            for char in characteristics {
                self.characteristics[char.uuid] = char
                
                let notifyUUIDs = [
                    BLEConstants.wifiListUUID,
                    BLEConstants.wifiStatusUUID,
                    BLEConstants.deviceStatusUUID
                ]
                
                if notifyUUIDs.contains(char.uuid) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            
            let requiredUUIDs = [
                BLEConstants.wifiListUUID,
                BLEConstants.wifiCredsUUID,
                BLEConstants.deviceStatusUUID,
                BLEConstants.commandUUID
            ]
            
            if requiredUUIDs.allSatisfy({ self.characteristics[$0] != nil }) {
                isReady = true
                requestStatus()
                scanWiFiNetworks()
            }
        }
    }
    
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        
        Task { @MainActor in
            switch characteristic.uuid {
            case BLEConstants.wifiListUUID:
                handleWiFiList(data: data)
            case BLEConstants.wifiStatusUUID:
                handleWiFiStatus(data: data)
            case BLEConstants.deviceStatusUUID:
                handleDeviceStatus(data: data)
            default:
                break
            }
        }
    }
}

// MARK: - Data Handlers

extension BluetoothService {
    
    private func handleWiFiList(data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let networks = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return
        }
        
        let parsedNetworks = networks.compactMap { dict -> WiFiNetwork? in
            guard let ssid = dict["ssid"] as? String,
                  let rssi = dict["rssi"] as? Int else {
                return nil
            }
            let secure = dict["secure"] as? Bool ?? true
            return WiFiNetwork(ssid: ssid, rssi: rssi, isSecure: secure)
        }.sorted { $0.rssi > $1.rssi }
        
        wifiNetworks = parsedNetworks
    }
    
    private func handleWiFiStatus(data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        if let status = dict["status"] as? String {
            switch status {
            case "connecting":
                wifiStatus = .connecting
            case "connected":
                let ip = dict["ip"] as? String ?? "unknown"
                wifiStatus = .connected(ip: ip)
            case "failed":
                let error = dict["error"] as? String ?? "Connection failed"
                wifiStatus = .failed(error: error)
            default:
                break
            }
        }
    }
    
    private func handleDeviceStatus(data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let status = try? JSONDecoder().decode(DeviceStatus.self, from: jsonData) else {
            return
        }
        
        deviceStatus = status
    }
}
