import SwiftUI
import Combine

// MARK: - Camera Align View

struct CameraAlignView: View {
    @EnvironmentObject var viewModel: SetupFlowViewModel
    @EnvironmentObject var bluetoothService: BluetoothService
    @EnvironmentObject var cameraService: CameraService
    
    // Frame tracking
    @State private var frameID: Int = 0
    @State private var displayedFrame: UIImage?
    
    // Stream state
    @State private var isStreamStarted = false
    @State private var isFlashOn = true
    
    // ROI state
    @State private var roiType: ROIType = .dial
    @State private var dialROI: ROIRect?
    @State private var spinnerROI: ROIRect?
    @State private var isDrawing = false
    @State private var drawStart: CGPoint = .zero
    @State private var drawRect: CGRect = .zero
    @State private var viewSize: CGSize = .zero
    
    // Cancellables for Combine
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        GeometryReader { geo in
            let camW = geo.size.width - 32
            let camH = camW * 0.75
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header
                    instruction.padding(.vertical, 12)
                    
                    ZStack {
                        // Camera feed
                        cameraFeed
                            .frame(width: camW, height: camH)
                            .cornerRadius(16)
                            .clipped()
                        
                        // ROI overlay
                        roiOverlay
                            .frame(width: camW, height: camH)
                            .cornerRadius(16)
                            .gesture(dragGesture)
                    }
                    .onAppear { viewSize = CGSize(width: camW, height: camH) }
                    
                    // Status bar
                    statusBar.padding(.top, 8)
                    
                    Spacer()
                    roiPicker.padding(.bottom, 16)
                    controls.padding(.bottom, 16)
                    confirmBtn.padding(.horizontal, 20).padding(.bottom, 30)
                }
            }
        }
        .onAppear { startEverything() }
        .onDisappear { stopEverything() }
    }
    
    // MARK: - Camera Feed
    
    @ViewBuilder
    private var cameraFeed: some View {
        if let frame = displayedFrame {
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(frameID)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    VStack(spacing: 12) {
                        if isStreamStarted {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.3)
                            Text("Waiting for camera...")
                                .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Starting camera...")
                                .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Button(action: restartStream) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry")
                            }
                            .font(Font(UIFont.systemFont(ofSize: 12, weight: .medium)))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
                        }
                    }
                )
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            // Connection indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(displayedFrame != nil ? Color.green : (isStreamStarted ? Color.orange : Color.red))
                    .frame(width: 8, height: 8)
                Text(displayedFrame != nil ? "Live" : (isStreamStarted ? "Connecting..." : "Offline"))
                    .font(Font(UIFont.systemFont(ofSize: 10, weight: .medium)))
            }
            
            Spacer()
            
            // Frame count
            if displayedFrame != nil {
                Text("Frame \(frameID)")
                    .font(Font(UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)))
            }
            
            // Mode indicator
            let mode = cameraService.streamingMode
            switch mode {
            case .wifi:
                Text("WiFi")
                    .font(Font(UIFont.systemFont(ofSize: 10, weight: .regular)))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.5))
                    .cornerRadius(4)
            case .ble:
                Text("BLE")
                    .font(Font(UIFont.systemFont(ofSize: 10, weight: .regular)))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.5))
                    .cornerRadius(4)
            case .none:
                EmptyView()
            }
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 24)
    }
    
    // MARK: - Stream Control
    
    private func startEverything() {
        print("📷 CameraAlignView appeared - starting stream")
        
        // Subscribe to frame updates from camera service
        cameraService.$currentFrame
            .receive(on: DispatchQueue.main)
            .sink { [self] frame in
                if let frame = frame {
                    self.displayedFrame = frame
                    self.frameID += 1
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to streaming mode changes
        cameraService.$streamingMode
            .receive(on: DispatchQueue.main)
            .sink { mode in
                print("📹 Streaming mode changed to: \(mode)")
            }
            .store(in: &cancellables)
        
        // Start the stream with a slight delay to ensure everything is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isStreamStarted = true
            self.cameraService.startCameraStream()
            
            // Turn on flash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.isFlashOn {
                    self.cameraService.setFlash(on: true)
                }
            }
            
            // Auto-retry if no frames after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if self.displayedFrame == nil && self.isStreamStarted {
                    print("⚠️ No frames received, attempting to restart stream...")
                    self.cameraService.startCameraStream()
                }
            }
        }
    }
    
    private func stopEverything() {
        print("📷 CameraAlignView disappearing - stopping stream")
        cancellables.removeAll()
        cameraService.stopCameraStream()
        cameraService.setFlash(on: false)
        isStreamStarted = false
    }
    
    private func restartStream() {
        print("📷 Restarting stream...")
        cameraService.stopCameraStream()
        displayedFrame = nil
        frameID = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.cameraService.startCameraStream()
            if self.isFlashOn {
                self.cameraService.setFlash(on: true)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button {
                stopEverything()
                viewModel.goBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(Font(UIFont.systemFont(ofSize: 16, weight: .medium)))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
            }
            
            Spacer()
            
            if bluetoothService.isConnected {
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text("BLE")
                }
                .font(Font(UIFont.systemFont(ofSize: 12, weight: .medium)))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Instruction
    
    private var instruction: some View {
        HStack(spacing: 8) {
            Image(systemName: roiType == .dial ? "number.square" : "arrow.triangle.2.circlepath")
                .foregroundColor(roiType == .dial ? .green : .orange)
            Text(instructionText)
                .font(Font(UIFont.systemFont(ofSize: 15, weight: .medium)))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.15))
        .cornerRadius(20)
    }
    
    private var instructionText: String {
        if roiType == .dial {
            return dialROI == nil ? "Draw around DIAL numbers" : "Dial set ✓"
        } else {
            return spinnerROI == nil ? "Draw around SPINNER" : "Spinner set ✓"
        }
    }
    
    // MARK: - ROI Drawing
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { v in
                if !isDrawing {
                    isDrawing = true
                    drawStart = v.startLocation
                }
                let minX = min(drawStart.x, v.location.x)
                let minY = min(drawStart.y, v.location.y)
                let w = abs(v.location.x - drawStart.x)
                let h = abs(v.location.y - drawStart.y)
                
                if roiType == .spinner {
                    let size = max(w, h)
                    drawRect = CGRect(x: minX, y: minY, width: size, height: size)
                } else {
                    drawRect = CGRect(x: minX, y: minY, width: w, height: h)
                }
            }
            .onEnded { _ in
                isDrawing = false
                guard drawRect.width > 30, drawRect.height > 30 else {
                    drawRect = .zero
                    return
                }
                
                let roi = ROIRect(x: drawRect.minX, y: drawRect.minY, width: drawRect.width, height: drawRect.height)
                
                withAnimation(.spring(response: 0.3)) {
                    if roiType == .dial {
                        dialROI = roi
                        if spinnerROI == nil { roiType = .spinner }
                    } else {
                        spinnerROI = roi
                    }
                }
                
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                drawRect = .zero
            }
    }
    
    private var roiOverlay: some View {
        Canvas { ctx, size in
            // Dim overlay
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.4)))
            
            // Dial ROI
            if let d = dialROI {
                let p = RoundedRectangle(cornerRadius: 8).path(in: d.cgRect)
                ctx.blendMode = .destinationOut
                ctx.fill(p, with: .color(.white))
                ctx.blendMode = .normal
                ctx.stroke(p, with: .color(.green), lineWidth: 3)
            }
            
            // Spinner ROI
            if let s = spinnerROI {
                let p = RoundedRectangle(cornerRadius: 8).path(in: s.cgRect)
                ctx.blendMode = .destinationOut
                ctx.fill(p, with: .color(.white))
                ctx.blendMode = .normal
                ctx.stroke(p, with: .color(.orange), lineWidth: 3)
            }
            
            // Current drawing
            if isDrawing && drawRect.width > 10 {
                let p = RoundedRectangle(cornerRadius: 8).path(in: drawRect)
                ctx.stroke(p, with: .color(roiType == .dial ? .green : .orange),
                          style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            }
        }
        .compositingGroup()
        .overlay(
            ZStack {
                if let d = dialROI { roiLabel("DIAL", .green, d) }
                if let s = spinnerROI { roiLabel("SPINNER", .orange, s) }
            }
        )
    }
    
    private func roiLabel(_ text: String, _ color: Color, _ roi: ROIRect) -> some View {
        Text(text)
            .font(Font(UIFont.systemFont(ofSize: 10, weight: .bold)))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
            .position(x: roi.x + roi.width/2, y: max(roi.y - 14, 14))
    }
    
    // MARK: - ROI Picker
    
    private var roiPicker: some View {
        HStack(spacing: 12) {
            roiButton("Dial", dialROI != nil ? "checkmark.circle.fill" : "number.square", roiType == .dial, .green) {
                roiType = .dial
            }
            roiButton("Spinner", spinnerROI != nil ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath", roiType == .spinner, .orange) {
                roiType = .spinner
            }
            
            if dialROI != nil || spinnerROI != nil {
                Button {
                    withAnimation {
                        if roiType == .dial { dialROI = nil }
                        else { spinnerROI = nil }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                        .foregroundColor(.red)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(20)
                }
            }
        }
    }
    
    private func roiButton(_ title: String, _ icon: String, _ selected: Bool, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(Font(UIFont.systemFont(ofSize: 15, weight: .semibold)))
            .foregroundColor(selected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selected ? color : Color.white.opacity(0.2))
            .cornerRadius(20)
        }
    }
    
    // MARK: - Controls
    
    private var controls: some View {
        HStack(spacing: 24) {
            // Flash
            controlButton(
                icon: isFlashOn ? "bolt.fill" : "bolt.slash.fill",
                label: "Flash",
                active: isFlashOn,
                color: .yellow
            ) {
                isFlashOn.toggle()
                cameraService.setFlash(on: isFlashOn)
            }
            
            // Play/Pause
            controlButton(
                icon: isStreamStarted ? "pause.fill" : "play.fill",
                label: isStreamStarted ? "Pause" : "Play",
                active: isStreamStarted && displayedFrame != nil,
                color: .green
            ) {
                if isStreamStarted {
                    cameraService.stopCameraStream()
                    isStreamStarted = false
                } else {
                    isStreamStarted = true
                    cameraService.startCameraStream()
                }
            }
            
            // Restart
            controlButton(icon: "arrow.clockwise", label: "Restart", active: false, color: .white) {
                restartStream()
            }
        }
    }
    
    private func controlButton(icon: String, label: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(active ? color : Color.white.opacity(0.2))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(Font(UIFont.systemFont(ofSize: 20, weight: .regular)))
                        .foregroundColor(active ? .black : .white)
                }
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Confirm
    
    private var confirmBtn: some View {
        Button(action: saveAndFinish) {
            HStack {
                Text(canConfirm ? "Confirm & Finish" : missingText)
                if canConfirm { Image(systemName: "checkmark") }
            }
            .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
            .foregroundColor(canConfirm ? .black : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canConfirm ? Color.green : Color.gray.opacity(0.3))
            .cornerRadius(14)
        }
        .disabled(!canConfirm)
    }
    
    private var canConfirm: Bool { dialROI != nil && spinnerROI != nil }
    
    private var missingText: String {
        if dialROI == nil && spinnerROI == nil { return "Draw both regions" }
        return dialROI == nil ? "Draw dial region" : "Draw spinner region"
    }
    
    private func saveAndFinish() {
        guard let d = dialROI, let s = spinnerROI else { return }
        stopEverything()
        
        let nd = d.normalized(in: viewSize)
        let ns = s.normalized(in: viewSize)
        
        viewModel.saveROIs(
            dialX: nd.x, dialY: nd.y, dialW: nd.width, dialH: nd.height,
            spinnerX: ns.x, spinnerY: ns.y, spinnerW: ns.width, spinnerH: ns.height
        )
    }
}
