import Foundation
import CoreBluetooth

// MARK: - WiFi Models

struct WiFiNetwork: Identifiable, Equatable {
    let id = UUID()
    let ssid: String
    let rssi: Int
    let isSecure: Bool
    
    var signalStrength: Int {
        switch rssi {
        case -50...0: return 3
        case -65 ..< -50: return 2
        case -80 ..< -65: return 1
        default: return 0
        }
    }
    
    var signalIcon: String {
        switch signalStrength {
        case 3: return "wifi"
        case 2: return "wifi"
        case 1: return "wifi.exclamationmark"
        default: return "wifi.slash"
        }
    }
    
    static func == (lhs: WiFiNetwork, rhs: WiFiNetwork) -> Bool {
        lhs.ssid == rhs.ssid
    }
}

enum WiFiConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(ip: String)
    case failed(error: String)
}

// MARK: - Streaming Models

enum StreamingMode: Equatable {
    case none
    case ble
    case wifi(url: String)
}

// MARK: - Camera Models

enum ROIType {
    case dial
    case spinner
}

struct ROIRect: Equatable {
    var x, y, width, height: CGFloat
    
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    
    func normalized(in size: CGSize) -> ROIRect {
        guard size.width > 0, size.height > 0 else { return self }
        return ROIRect(
            x: x / size.width,
            y: y / size.height,
            width: width / size.width,
            height: height / size.height
        )
    }
}

// MARK: - Setup Flow

enum SetupState {
    case welcome
    case modeSelection
    case scanning
    case labelInput
    case wifiInput
    case cameraAlign
    case dashboard
}

// MARK: - BLE Constants

struct BLEConstants {
    static let serviceUUID = CBUUID(string: "4F4B4F00-0001-0001-0001-4F4B4F444556")
    static let wifiListUUID = CBUUID(string: "4F4B4F01-0001-0001-0001-4F4B4F444556")
    static let wifiCredsUUID = CBUUID(string: "4F4B4F02-0001-0001-0001-4F4B4F444556")
    static let wifiStatusUUID = CBUUID(string: "4F4B4F03-0001-0001-0001-4F4B4F444556")
    static let cameraFrameUUID = CBUUID(string: "4F4B4F04-0001-0001-0001-4F4B4F444556")
    static let cameraCtrlUUID = CBUUID(string: "4F4B4F05-0001-0001-0001-4F4B4F444556")
    static let roiConfigUUID = CBUUID(string: "4F4B4F06-0001-0001-0001-4F4B4F444556")
    static let deviceStatusUUID = CBUUID(string: "4F4B4F07-0001-0001-0001-4F4B4F444556")
    static let deviceConfigUUID = CBUUID(string: "4F4B4F08-0001-0001-0001-4F4B4F444556")
    static let commandUUID = CBUUID(string: "4F4B4F09-0001-0001-0001-4F4B4F444556")
    static let deviceNamePrefix = "Oko"
    static let savedDevicesKey = "SavedOkoDevices"
}
