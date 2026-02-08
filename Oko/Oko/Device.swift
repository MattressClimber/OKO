import Foundation

// MARK: - Device Model

struct OkoDevice: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var type: DeviceType
    var installDate: Date
    var lastReading: String
    var status: DeviceStatus
    var batteryPercent: Int
    var peripheralIdentifier: String?
    
    enum DeviceType: String, Codable, CaseIterable {
        case water = "Water"
        case gauge = "Gauge"
        
        var icon: String {
            switch self {
            case .water: return "drop.fill"
            case .gauge: return "gauge"
            }
        }
    }
    
    enum DeviceStatus: String, Codable {
        case learning
        case ok
        case leakDetected
        case offline
        
        var displayText: String {
            switch self {
            case .learning: return "Learning Baseline"
            case .ok: return "Everything is currently okay."
            case .leakDetected: return "Problem Detected!"
            case .offline: return "Device Offline"
            }
        }
    }
    
    static func == (lhs: OkoDevice, rhs: OkoDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BLE Device Status (from BLE responses)
// Renamed to avoid conflict with OkoDevice.DeviceStatus enum

struct BLEDeviceStatus: Codable {
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
    let mlEnabled: Bool?
}
