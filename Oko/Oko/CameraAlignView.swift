import SwiftUI

enum ROIType {
    case dial
    case spinner
}

struct ROIRect: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    
    // Convert to normalized coordinates (0-1) relative to container
    func normalized(in containerSize: CGSize) -> ROIRect {
        ROIRect(
            x: x / containerSize.width,
            y: y / containerSize.height,
            width: width / containerSize.width,
            height: height / containerSize.height
        )
    }
}

struct CameraAlignView: View {
    @EnvironmentObject var manager: SetupManager
    @State private var isFlashOn = true
    @State private var frameCount = 0
    @State private var hasStartedStream = false
    
    // ROI drawing state
    @State private var currentROIType: ROIType = .dial
    @State private var dialROI: ROIRect?
    @State private var spinnerROI: ROIRect?
    @State private var isDrawing = false
    @State private var drawStart: CGPoint = .zero
    @State private var currentDrawRect: CGRect = .zero
    
    // Video feed size for coordinate calculation
    @State private var videoSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    header
                        .padding(.top, 8)
                    
                    // Instructions
                    instructionBanner
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    // Camera feed with drawable overlay
                    ZStack {
                        // Camera feed
                        cameraFeedView
                            .frame(width: geometry.size.width - 32, height: (geometry.size.width - 32) * 0.75)
                            .clipped()
                            .cornerRadius(16)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.onAppear {
                                        videoSize = geo.size
                                    }
                                }
                            )
                        
                        // Drawing overlay
                        drawingOverlay
                            .frame(width: geometry.size.width - 32, height: (geometry.size.width - 32) * 0.75)
                            .cornerRadius(16)
                            .gesture(drawGesture)
                        
                        // ROI labels
                        roiLabels
                            .frame(width: geometry.size.width - 32, height: (geometry.size.width - 32) * 0.75)
                    }
                    
                    Spacer()
                    
                    // ROI type selector
                    roiTypeSelector
                        .padding(.bottom, 12)
                    
                    // Control buttons
                    controlButtons
                        .padding(.bottom, 16)
                    
                    // Confirm button
                    confirmButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            startStreamingIfNeeded()
        }
        .onDisappear {
            stopStreamingIfNeeded()
        }
        .onReceive(manager.bleManager.$currentFrame) { newFrame in
            if newFrame != nil {
                frameCount += 1
            }
        }
    }
    
    // MARK: - Drawing Gesture
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDrawing {
                    isDrawing = true
                    drawStart = value.startLocation
                }
                
                let minX = min(drawStart.x, value.location.x)
                let minY = min(drawStart.y, value.location.y)
                let width = abs(value.location.x - drawStart.x)
                let height = abs(value.location.y - drawStart.y)
                
                // For spinner, enforce square aspect ratio
                if currentROIType == .spinner {
                    let size = max(width, height)
                    currentDrawRect = CGRect(x: minX, y: minY, width: size, height: size)
                } else {
                    currentDrawRect = CGRect(x: minX, y: minY, width: width, height: height)
                }
            }
            .onEnded { value in
                isDrawing = false
                
                // Only save if the rectangle is large enough
                if currentDrawRect.width > 30 && currentDrawRect.height > 30 {
                    let roi = ROIRect(
                        x: currentDrawRect.minX,
                        y: currentDrawRect.minY,
                        width: currentDrawRect.width,
                        height: currentDrawRect.height
                    )
                    
                    withAnimation(.spring(response: 0.3)) {
                        if currentROIType == .dial {
                            dialROI = roi
                            // Auto-switch to spinner after drawing dial
                            if spinnerROI == nil {
                                currentROIType = .spinner
                            }
                        } else {
                            spinnerROI = roi
                        }
                    }
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }
                
                currentDrawRect = .zero
            }
    }
    
    // MARK: - Drawing Overlay
    private var drawingOverlay: some View {
        Canvas { context, size in
            // Semi-transparent overlay
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.4)))
            
            // Cut out and draw dial ROI
            if let dial = dialROI {
                let dialPath = RoundedRectangle(cornerRadius: 8).path(in: dial.cgRect)
                
                // Cut out the region
                context.blendMode = .destinationOut
                context.fill(dialPath, with: .color(.white))
                
                // Draw border
                context.blendMode = .normal
                context.stroke(dialPath, with: .color(.green), lineWidth: 3)
            }
            
            // Cut out and draw spinner ROI
            if let spinner = spinnerROI {
                let spinnerPath = RoundedRectangle(cornerRadius: 8).path(in: spinner.cgRect)
                
                context.blendMode = .destinationOut
                context.fill(spinnerPath, with: .color(.white))
                
                context.blendMode = .normal
                context.stroke(spinnerPath, with: .color(.orange), lineWidth: 3)
            }
            
            // Draw current drawing rectangle
            if isDrawing && currentDrawRect.width > 10 {
                let color: Color = currentROIType == .dial ? .green : .orange
                let drawPath = RoundedRectangle(cornerRadius: 8).path(in: currentDrawRect)
                
                context.blendMode = .normal
                context.stroke(drawPath, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            }
        }
        .compositingGroup()
    }
    
    // MARK: - ROI Labels
    private var roiLabels: some View {
        ZStack {
            if let dial = dialROI {
                Text("DIAL")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
                    .position(x: dial.x + dial.width / 2, y: dial.y - 12)
            }
            
            if let spinner = spinnerROI {
                Text("SPINNER")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(4)
                    .position(x: spinner.x + spinner.width / 2, y: spinner.y - 12)
            }
        }
    }
    
    // MARK: - Instruction Banner
    private var instructionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: currentROIType == .dial ? "number.square" : "arrow.triangle.2.circlepath")
                .foregroundColor(currentROIType == .dial ? .green : .orange)
            
            Text(instructionText)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.15))
        .cornerRadius(20)
    }
    
    private var instructionText: String {
        if currentROIType == .dial {
            if dialROI == nil {
                return "Draw a rectangle around the DIAL numbers"
            } else {
                return "Dial set! Tap to redraw or continue"
            }
        } else {
            if spinnerROI == nil {
                return "Draw a square around the SPINNER"
            } else {
                return "Spinner set! Review and confirm"
            }
        }
    }
    
    // MARK: - ROI Type Selector
    private var roiTypeSelector: some View {
        HStack(spacing: 16) {
            // Dial button
            Button(action: { currentROIType = .dial }) {
                HStack(spacing: 6) {
                    Image(systemName: dialROI != nil ? "checkmark.circle.fill" : "number.square")
                    Text("Dial")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(currentROIType == .dial ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(currentROIType == .dial ? Color.green : Color.white.opacity(0.2))
                .cornerRadius(20)
            }
            
            // Spinner button
            Button(action: { currentROIType = .spinner }) {
                HStack(spacing: 6) {
                    Image(systemName: spinnerROI != nil ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    Text("Spinner")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(currentROIType == .spinner ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(currentROIType == .spinner ? Color.orange : Color.white.opacity(0.2))
                .cornerRadius(20)
            }
            
            // Clear button
            if dialROI != nil || spinnerROI != nil {
                Button(action: {
                    withAnimation {
                        if currentROIType == .dial {
                            dialROI = nil
                        } else {
                            spinnerROI = nil
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(20)
                }
            }
        }
    }
    
    // MARK: - Stream Control
    private func startStreamingIfNeeded() {
        guard !hasStartedStream else { return }
        print("📷 CameraAlignView - starting stream")
        hasStartedStream = true
        manager.startCameraStream()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.isFlashOn {
                self.manager.bleManager.setFlash(on: true)
            }
        }
    }
    
    private func stopStreamingIfNeeded() {
        guard hasStartedStream else { return }
        print("📷 CameraAlignView - stopping stream")
        hasStartedStream = false
        manager.stopCameraStream()
        manager.bleManager.setFlash(on: false)
    }
    
    // MARK: - Camera Feed View
    @ViewBuilder
    private var cameraFeedView: some View {
        if let frame = manager.bleManager.currentFrame {
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(frameCount)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    VStack(spacing: 12) {
                        if manager.bleManager.isStreaming {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            Text("Waiting for camera...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Tap Play to start")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                )
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Button(action: { 
                stopStreamingIfNeeded()
                manager.goBack() 
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
            }

            Spacer()
            
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(manager.bleManager.currentFrame != nil ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(manager.bleManager.currentFrame != nil ? "Live" : "Connecting")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.15))
            .cornerRadius(20)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Control Buttons
    private var controlButtons: some View {
        HStack(spacing: 24) {
            // Flash toggle
            Button(action: {
                isFlashOn.toggle()
                manager.bleManager.setFlash(on: isFlashOn)
            }) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isFlashOn ? Color.yellow : Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                        Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isFlashOn ? .black : .white)
                    }
                    Text("Flash")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Stream toggle
            Button(action: {
                if manager.bleManager.isStreaming {
                    manager.stopCameraStream()
                    hasStartedStream = false
                } else {
                    manager.startCameraStream()
                    hasStartedStream = true
                }
            }) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(manager.bleManager.isStreaming ? Color.green : Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                        Image(systemName: manager.bleManager.isStreaming ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(manager.bleManager.isStreaming ? .black : .white)
                    }
                    Text(manager.bleManager.isStreaming ? "Pause" : "Play")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Confirm Button
    private var confirmButton: some View {
        Button(action: {
            guard let dial = dialROI, let spinner = spinnerROI else { return }
            
            stopStreamingIfNeeded()
            
            // Normalize ROIs to 0-1 range
            let normalizedDial = dial.normalized(in: videoSize)
            let normalizedSpinner = spinner.normalized(in: videoSize)
            
            print("🎯 Dial ROI: x=\(normalizedDial.x), y=\(normalizedDial.y), w=\(normalizedDial.width), h=\(normalizedDial.height)")
            print("🎯 Spinner ROI: x=\(normalizedSpinner.x), y=\(normalizedSpinner.y), w=\(normalizedSpinner.width), h=\(normalizedSpinner.height)")
            
            // Save both ROIs
            manager.saveROIs(
                dialX: normalizedDial.x, dialY: normalizedDial.y,
                dialW: normalizedDial.width, dialH: normalizedDial.height,
                spinnerX: normalizedSpinner.x, spinnerY: normalizedSpinner.y,
                spinnerW: normalizedSpinner.width, spinnerH: normalizedSpinner.height
            )
        }) {
            HStack {
                if canConfirm {
                    Text("Confirm & Finish Setup")
                    Image(systemName: "checkmark")
                } else {
                    Text(missingROIText)
                }
            }
            .font(.headline)
            .foregroundColor(canConfirm ? .black : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canConfirm ? Color.green : Color.gray.opacity(0.3))
            .cornerRadius(14)
        }
        .disabled(!canConfirm)
    }
    
    private var canConfirm: Bool {
        dialROI != nil && spinnerROI != nil
    }
    
    private var missingROIText: String {
        if dialROI == nil && spinnerROI == nil {
            return "Draw dial and spinner regions"
        } else if dialROI == nil {
            return "Draw dial region first"
        } else {
            return "Draw spinner region"
        }
    }
}
