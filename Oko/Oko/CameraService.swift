import Foundation
import UIKit
import Combine

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
    private var cancellables = Set<AnyCancellable>()
    private var streamBootstrapTask: Task<Void, Never>?
    
    // BLE Frame assembly
    private var frameBuffer = Data()
    private var expectedFrameSize = 0
    private var expectedPackets = 0
    private var receivedPackets = Set<Int>()
    
    // WiFi streaming
    private var wifiStreamTask: Task<Void, Never>?
    private var wifiStreamURL: URL?
    private var wifiFallbackQueue: [URL] = []
    private var wifiFailuresOnCurrentURL = 0
    
    //MARK: - Setup
    
    func setupWith(bluetoothService: BluetoothService) {
        self.bluetoothService = bluetoothService

        cancellables.removeAll()

        bluetoothService.$cameraStreamSignal
            .receive(on: RunLoop.main)
            .sink { [weak self] signal in
                guard let self = self, self.isStreaming else { return }

                switch signal {
                case .unknown:
                    break
                case .ble:
                    self.stopWiFiStreaming()
                    self.streamingMode = .ble
                    self.resetBLEFrameAssembly()
                case .wifi(let url):
                    let candidates = self.buildWiFiStreamCandidates(from: bluetoothService, preferredURL: url)
                    guard let primary = candidates.first else {
                        self.stopWiFiStreaming()
                        self.streamingMode = .ble
                        return
                    }
                    self.startWiFiStreaming(url: primary, fallbackURLs: Array(candidates.dropFirst()))
                }
            }
            .store(in: &cancellables)

        bluetoothService.$cameraFrameChunk
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] chunk in
                guard let self = self else { return }
                guard self.isStreaming else { return }
                if case .wifi = self.streamingMode { return }
                self.handleCameraFrame(data: chunk)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Commands
    
    func startCameraStream() {
        guard let service = bluetoothService else {
            print("❌ No Bluetooth service available")
            return
        }
        
        isStreaming = true
        stopWiFiStreaming()
        resetBLEFrameAssembly()
        streamBootstrapTask?.cancel()
        print("📹 Starting camera stream")

        // Always let firmware decide transport mode; it will publish a camera signal.
        service.startCameraStream()

        // Backward-compatibility fallback for firmware that doesn't publish mode.
        streamBootstrapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self = self,
                  self.isStreaming,
                  service.cameraStreamSignal == .unknown else { return }

            if let fallbackURL = self.deriveDefaultWiFiStreamURL(from: service) {
                let candidates = self.buildWiFiStreamCandidates(from: service, preferredURL: fallbackURL)
                guard let primary = candidates.first else { return }
                self.startWiFiStreaming(url: primary, fallbackURLs: Array(candidates.dropFirst()))
            } else {
                self.streamingMode = .ble
                print("📹 BLE streaming mode activated (fallback)")
            }
        }
    }
    
    func stopCameraStream() {
        isStreaming = false
        streamingMode = .none
        streamBootstrapTask?.cancel()
        streamBootstrapTask = nil
        stopWiFiStreaming()
        bluetoothService?.stopCameraStream()
        resetBLEFrameAssembly()
        print("📹 Stopping camera stream")
    }
    
    func setFlash(on: Bool) {
        bluetoothService?.setFlash(on: on)
        print("💡 Flash: \(on ? "ON" : "OFF")")
    }
    
    // MARK: - WiFi Streaming
    
    func startWiFiStreaming(url: String, fallbackURLs: [String] = []) {
        guard let streamURL = URL(string: url) else { return }
        
        stopWiFiStreaming()
        wifiStreamURL = streamURL
        wifiFallbackQueue = fallbackURLs.compactMap(URL.init(string:))
        wifiFailuresOnCurrentURL = 0
        streamingMode = .wifi(url: url)
        
        wifiStreamTask = Task {
            await streamWiFiFrames()
        }
    }
    
    private func stopWiFiStreaming() {
        wifiStreamTask?.cancel()
        wifiStreamTask = nil
        wifiStreamURL = nil
        wifiFallbackQueue = []
        wifiFailuresOnCurrentURL = 0
    }
    
    private func streamWiFiFrames() async {
        while !Task.isCancelled {
            guard let url = wifiStreamURL else { return }

            do {
                let request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: 30
                )
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                var buffer = Data()
                buffer.reserveCapacity(256 * 1024)

                for try await byte in bytes {
                    if Task.isCancelled { return }

                    buffer.append(byte)

                    while let frameData = tryDecodeJPEGFrame(from: &buffer) {
                        if let image = UIImage(data: frameData) {
                            currentFrame = image
                            frameCount += 1
                        }
                    }

                    if buffer.count > 4_000_000 {
                        buffer.removeFirst(buffer.count - 2_000_000)
                    }
                }

                wifiFailuresOnCurrentURL = 0
                try? await Task.sleep(for: .milliseconds(80))
            } catch {
                if !Task.isCancelled {
                    print("Error fetching stream frame: \(error.localizedDescription)")
                }
                wifiFailuresOnCurrentURL += 1
                if wifiFailuresOnCurrentURL >= 2, !wifiFallbackQueue.isEmpty {
                    wifiStreamURL = wifiFallbackQueue.removeFirst()
                    wifiFailuresOnCurrentURL = 0
                    if let next = wifiStreamURL?.absoluteString {
                        streamingMode = .wifi(url: next)
                        print("📹 Switching WiFi stream endpoint: \(next)")
                    }
                    continue
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func deriveDefaultWiFiStreamURL(from service: BluetoothService) -> String? {
        guard case .connected(let ip) = service.wifiStatus else { return nil }
        guard ip != "saved", ip != "unknown", ip.contains(".") else { return nil }
        return "http://\(ip):81/capture"
    }

    private func buildWiFiStreamCandidates(from service: BluetoothService, preferredURL: String?) -> [String] {
        guard case .connected(let ip) = service.wifiStatus,
              ip != "saved", ip != "unknown", ip.contains(".") else {
            return preferredURL.map { [$0] } ?? []
        }

        let defaults = [
            "http://\(ip):81/capture",
            "http://\(ip):8080/stream",
            "http://\(ip):8080/capture"
        ]

        var ordered: [String] = []
        if let preferredURL, !preferredURL.isEmpty {
            ordered.append(preferredURL)
        }

        for url in defaults where !ordered.contains(url) {
            ordered.append(url)
        }
        return ordered
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

        if expectedPackets > 0 && receivedPackets.count < expectedPackets {
            resetBLEFrameAssembly()
            return
        }

        if expectedFrameSize > 0 && frameBuffer.count != expectedFrameSize {
            resetBLEFrameAssembly()
            return
        }
        
        if let image = UIImage(data: frameBuffer) {
            currentFrame = image
            frameCount += 1
        }
        
        resetBLEFrameAssembly()
    }

    private func resetBLEFrameAssembly() {
        frameBuffer = Data()
        expectedPackets = 0
        expectedFrameSize = 0
        receivedPackets.removeAll()
    }

    private func tryDecodeJPEGFrame(from buffer: inout Data) -> Data? {
        let startMarker = Data([0xFF, 0xD8])
        let endMarker = Data([0xFF, 0xD9])

        guard let start = buffer.range(of: startMarker) else {
            return nil
        }

        if start.lowerBound > 0 {
            buffer.removeSubrange(..<start.lowerBound)
        }

        guard let end = buffer.range(of: endMarker, in: start.lowerBound..<buffer.endIndex) else {
            return nil
        }

        let frame = buffer.subdata(in: start.lowerBound..<end.upperBound)
        buffer.removeSubrange(..<end.upperBound)
        return frame
    }
}
