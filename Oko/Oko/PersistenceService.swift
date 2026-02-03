import Foundation

// MARK: - Persistence Service

@MainActor
final class PersistenceService: ObservableObject {
    
    static let shared = PersistenceService()
    
    @Published var devices: [OkoDevice] = []
    @Published var currentDeviceIndex: Int = 0
    
    var activeDevice: OkoDevice? {
        devices.indices.contains(currentDeviceIndex) ? devices[currentDeviceIndex] : nil
    }
    
    private init() {
        loadDevices()
    }
    
    // MARK: - Public Methods
    
    func saveDevice(_ device: OkoDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
            currentDeviceIndex = devices.count - 1
        }
        saveDevices()
    }
    
    func updateDevice(_ device: OkoDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
        saveDevices()
    }
    
    func deleteDevice(_ device: OkoDevice) {
        devices.removeAll { $0.id == device.id }
        saveDevices()
        
        if devices.isEmpty {
            currentDeviceIndex = 0
        } else if currentDeviceIndex >= devices.count {
            currentDeviceIndex = devices.count - 1
        }
    }
    
    func deleteDevices(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        saveDevices()
        
        if devices.isEmpty {
            currentDeviceIndex = 0
        } else if currentDeviceIndex >= devices.count {
            currentDeviceIndex = devices.count - 1
        }
    }
    
    // MARK: - Private Methods
    
    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: BLEConstants.savedDevicesKey)
        }
    }
    
    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: BLEConstants.savedDevicesKey),
           let decoded = try? JSONDecoder().decode([OkoDevice].self, from: data) {
            devices = decoded
        }
    }
}
