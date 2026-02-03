import Foundation
import CoreBluetooth

// MARK: - BLE Protocol Constants

struct BLEConstants {
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
    
    // Device naming
    static let deviceNamePrefix = "Oko"
    
    // Persistence keys
    static let savedDevicesKey = "SavedOkoDevices"
}
