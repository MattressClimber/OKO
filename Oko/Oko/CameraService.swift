import Foundation
import UIKit
import Combine
import CoreBluetooth

// MARK: - Camera Service

@MainActor
final class CameraService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentFrame: UIImage?
    @Published var isStreaming = false
    @Published var streamingMode: StreamingMode = .none
    @Published var frameCount = 0
    
    // MARK: - Private Properties
    
    private weak var bluetoothService: BluetoothService?
    
    // BLE Frame assembly
    private var frameBuffer = Data()
    private var expectedFrameSize = 0
    private var expectedPackets = 0
    private var receivedPackets = Set<Int>()
    
    // WiFi streaming
    private var wifiStreamTask: Task<Void, Never>?
    private var wifiStreamURL: URL?
    
    //MARK: - Setup
    
    func setupWith(bluetoothService: BluetoothService) {
        self.bluetoothService = bluetoothService
    }
    
    // MARK: - Commands
    
    func startCameraStream() {
        guard let service = bluetoothService,
              let peripheral = service.connectedPeripheral,
              let data = "start_stream".data(using: .utf8) else {
            return
        }
        
        isStreaming = true
        // This would write to camera control characteristic
        // For now, simplified
        print("📹 Starting camera stream")
    }
    
    func stopCameraStream() {
        isStreaming = false
        streamingMode = .none
        stopWiFiStreaming()
        print("📹 Stopping camera stream")
    }
    
    func setFlash(on: Bool) {
        print("💡 Flash: \(on ? "ON" : "OFF")")
    }
    
    // MARK: - WiFi Streaming
    
    func startWiFiStreaming(url: String) {
        guard let streamURL = URL(string: url) else { return }
        
        wifiStreamURL = streamURL
        streamingMode = .wifi(url: url)
        
        wifiStreamTask = Task {
            await streamWiFiFrames()
        }
    }
    
    private func stopWiFiStreaming() {
        wifiStreamTask?.cancel()
        wifiStreamTask = nil
        wifiStreamURL = nil
    }
    
    private func streamWiFiFrames() async {
        guard let url = wifiStreamURL else { return }
        
        while !Task.isCancelled {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let image = UIImage(data: data) {
                    currentFrame = image
                    frameCount += 1
                }
                
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                if !Task.isCancelled {
                    print("Error fetching frame")
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    // MARK: - BLE Frame Handling
    
    func handleCameraFrame(data: Data) {
        if let str = String(data: data, encoding: .utf8) {
            if str.hasPrefix("FRAME:") {
                let parts = str.split(separator: ":")
                if parts.count == 3,
                   let packets = Int(parts[1]),
                   let size = Int(parts[2]) {
                    frameBuffer = Data()
                    frameBuffer.reserveCapacity(size)
                    expectedPackets = packets
                    expectedFrameSize = size
                    receivedPackets.removeAll()
                }
                return
            }
            
            if str == "FRAME_END" {
                assembleBLEFrame()
                return
            }
        }
        
        processBLEFrameChunk(data: data)
    }
    
    private func processBLEFrameChunk(data: Data) {
        guard data.count > 2 else { return }
        
        let packetNum = Int(data[0]) << 8 | Int(data[1])
        let chunkData = data.subdata(in: 2..<data.count)
        
        frameBuffer.append(chunkData)
        receivedPackets.insert(packetNum)
    }
    
    private func assembleBLEFrame() {
        guard frameBuffer.count > 0 else { return }
        
        if let image = UIImage(data: frameBuffer) {
            currentFrame = image
            frameCount += 1
        }
        
        frameBuffer = Data()
        expectedPackets = 0
        expectedFrameSize = 0
        receivedPackets.removeAll()
    }
}
