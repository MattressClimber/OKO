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
    // Fields from v2.5 firmware
    let battery: Int?
    let wifiConfigured: Bool?
    let wifiConnected: Bool?
    let ssid: String?
    let ip: String?
    let roiConfigured: Bool?
    let lastReading: Int?
    let mlEnabled: Bool?
    let version: String?
    
    // Legacy fields from v1.x firmware (optional for backwards compat)
    let label: String?
    let type: String?
    let baselineComplete: Bool?
    let baselineDays: Int?
    let photos: Int?
    let boots: Int?
    
    // Allow decoding to succeed even if fields are missing
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        battery = try container.decodeIfPresent(Int.self, forKey: .battery)
        wifiConfigured = try container.decodeIfPresent(Bool.self, forKey: .wifiConfigured)
        wifiConnected = try container.decodeIfPresent(Bool.self, forKey: .wifiConnected)
        ssid = try container.decodeIfPresent(String.self, forKey: .ssid)
        ip = try container.decodeIfPresent(String.self, forKey: .ip)
        roiConfigured = try container.decodeIfPresent(Bool.self, forKey: .roiConfigured)
        lastReading = try container.decodeIfPresent(Int.self, forKey: .lastReading)
        mlEnabled = try container.decodeIfPresent(Bool.self, forKey: .mlEnabled)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        baselineComplete = try container.decodeIfPresent(Bool.self, forKey: .baselineComplete)
        baselineDays = try container.decodeIfPresent(Int.self, forKey: .baselineDays)
        photos = try container.decodeIfPresent(Int.self, forKey: .photos)
        boots = try container.decodeIfPresent(Int.self, forKey: .boots)
    }
}
