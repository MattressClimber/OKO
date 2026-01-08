import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    var centralManager: CBCentralManager?
    private var targetName = "Oko"
    
    // CHANGED: We now hold a LIST of devices
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isBluetoothPoweredOn: Bool = false
    @Published var isConnected: Bool = false
    
    // We keep track of the one we are actively trying to talk to
    var connectedPeripheral: CBPeripheral?
    
    override init() {
        super.init()
    }
    
    func startScanning() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
            return
        }
        
        if centralManager?.state == .poweredOn {
            print("🔍 Scanning for \(targetName)...")
            // Reset list on new scan
            discoveredDevices.removeAll()
            centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
    }
    
    // CHANGED: Now accepts a specific device to connect to
    func connect(to device: CBPeripheral) {
        self.connectedPeripheral = device
        centralManager?.stopScan()
        print("🔗 Connecting to \(device.name ?? "Unknown")...")
        centralManager?.connect(device, options: nil)
    }
    
    func disconnect() {
        if let device = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(device)
        }
    }
    
    // MARK: - Delegate Methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            isBluetoothPoweredOn = true
            startScanning()
        } else {
            isBluetoothPoweredOn = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Filter: Must have name containing "Oko"
        if let name = peripheral.name, name.localizedCaseInsensitiveContains(targetName) {
            
            // Avoid duplicates
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                print("🔎 Found: \(name)")
                DispatchQueue.main.async {
                    self.discoveredDevices.append(peripheral)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("🎉 Connected to \(peripheral.name ?? "Device")")
        DispatchQueue.main.async {
            self.isConnected = true
        }
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Connection Failed")
    }
}
