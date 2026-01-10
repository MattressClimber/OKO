import SwiftUI
import Combine

struct WifiInputView: View {
    @EnvironmentObject var manager: SetupManager
    @FocusState private var isPasswordFocused: Bool
    @State private var showPassword = false
    @State private var isRefreshing = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        ZStack {
            // Background
            Color("BackgroundTheme")
                .ignoresSafeArea()
                .onTapGesture {
                    isPasswordFocused = false
                }
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Title
                titleSection
                
                // Content
                if manager.bleManager.wifiNetworks.isEmpty && !isRefreshing {
                    emptyState
                } else if manager.bleManager.wifiNetworks.isEmpty {
                    loadingState
                } else {
                    networkList
                }
            }
            
            // Bottom panel (appears when network selected)
            if manager.selectedWiFiNetwork != nil {
                VStack {
                    Spacer()
                    bottomPanel
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.selectedWiFiNetwork != nil)
        .onAppear {
            startAutoRefresh()
            // Initial scan
            if manager.bleManager.wifiNetworks.isEmpty {
                performWiFiScan()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    // MARK: - Auto Refresh
    private func startAutoRefresh() {
        // Refresh every 5 seconds if no networks
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if manager.bleManager.wifiNetworks.isEmpty && !isRefreshing {
                performWiFiScan()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - WiFi Scan Logic
    private func performWiFiScan() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        manager.refreshWiFiNetworks()
        
        // Reset refreshing state after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            isRefreshing = false
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Button(action: {
                if isPasswordFocused {
                    isPasswordFocused = false
                } else {
                    manager.goBack()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Network count badge
            if !manager.bleManager.wifiNetworks.isEmpty {
                Text("\(manager.bleManager.wifiNetworks.count) networks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }
            
            // Refresh button with animation
            Button(action: {
                performWiFiScan()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
            }
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Title Section
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect to WiFi")
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
            
            Text("Select your 2.4GHz network for best range")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No networks found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button(action: performWiFiScan) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan Again")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(20)
            }
            
            Text("Make sure you're near your router\nand the device is powered on")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.3)
            
            Text("Scanning for networks...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Network List
    private var networkList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(manager.bleManager.wifiNetworks) { network in
                        NetworkRow(
                            network: network,
                            isSelected: manager.selectedWiFiNetwork?.ssid == network.ssid
                        )
                        .id(network.ssid)
                        .onTapGesture {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if manager.selectedWiFiNetwork?.ssid == network.ssid {
                                    manager.selectedWiFiNetwork = nil
                                    manager.wifiPassword = ""
                                    isPasswordFocused = false
                                } else {
                                    manager.selectedWiFiNetwork = network
                                    manager.wifiPassword = ""
                                    if network.isSecure {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            isPasswordFocused = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, manager.selectedWiFiNetwork != nil ? 300 : 20)
            }
            .onChange(of: manager.selectedWiFiNetwork) { selected in
                if let ssid = selected?.ssid {
                    withAnimation {
                        proxy.scrollTo(ssid, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Bottom Panel
    private var bottomPanel: some View {
        VStack(spacing: 16) {
            // Connection status banner
            if manager.isConnectingToWiFi {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Testing connection...")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(10)
            }
            
            // Error message
            if let error = manager.wifiConnectionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Retry") {
                        manager.wifiConnectionError = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
            }
            
            // Password field
            if let network = manager.selectedWiFiNetwork, network.isSecure {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    ZStack(alignment: .leading) {
                        if manager.wifiPassword.isEmpty {
                            Text("Password")
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        
                        if showPassword {
                            TextField("", text: $manager.wifiPassword)
                                .focused($isPasswordFocused)
                                .submitLabel(.join)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit(submitPassword)
                        } else {
                            SecureField("", text: $manager.wifiPassword)
                                .focused($isPasswordFocused)
                                .submitLabel(.join)
                                .onSubmit(submitPassword)
                        }
                    }
                    
                    // Show/hide password
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showPassword.toggle()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isPasswordFocused = true
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPasswordFocused ? Color.green : Color.clear, lineWidth: 2)
                )
                .disabled(manager.isConnectingToWiFi)
            }
            
            // Connect Button
            Button(action: submitPassword) {
                HStack(spacing: 8) {
                    if manager.isConnectingToWiFi {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        Text("Connecting...")
                    } else {
                        Text("Connect")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.headline)
                .foregroundColor(canConnect ? .black : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canConnect ? Color.green : Color.gray.opacity(0.3))
                .cornerRadius(14)
            }
            .disabled(!canConnect)
        }
        .padding(24)
        .background(
            Color("BackgroundTheme")
                .shadow(color: .black.opacity(0.1), radius: 20, y: -10)
        )
        .cornerRadius(24, corners: [.topLeft, .topRight])
    }
    
    // MARK: - Helpers
    private var canConnect: Bool {
        guard let network = manager.selectedWiFiNetwork else { return false }
        if manager.isConnectingToWiFi { return false }
        if network.isSecure && manager.wifiPassword.isEmpty { return false }
        return true
    }
    
    private func submitPassword() {
        guard canConnect else { return }
        isPasswordFocused = false
        manager.connectToSelectedWiFi()
    }
}

// MARK: - Network Row
struct NetworkRow: View {
    let network: WiFiNetwork
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: signalIcon)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .black : .primary)
                .frame(width: 24)
            
            Text(network.ssid)
                .font(.body.weight(.medium))
                .foregroundColor(isSelected ? .black : .primary)
                .lineLimit(1)
            
            Spacer()
            
            if network.isSecure {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(isSelected ? .black.opacity(0.6) : .secondary)
            }
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isSelected ? Color.green : Color.gray.opacity(0.08))
        .cornerRadius(12)
    }
    
    private var signalIcon: String {
        switch network.signalStrength {
        case 3: return "wifi"
        case 2: return "wifi"
        case 1: return "wifi.exclamationmark"
        default: return "wifi.slash"
        }
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
