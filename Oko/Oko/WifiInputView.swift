import SwiftUI

import SwiftUI

struct WifiInputView: View {
    @EnvironmentObject var viewModel: SetupFlowViewModel
    @EnvironmentObject var bluetoothService: BluetoothService
    @FocusState private var isPasswordFocused: Bool
    @State private var showPassword = false
    @State private var refreshTimer: Timer?
    
    private var isRefreshing: Bool { viewModel.isRefreshingWiFi }
    
    var body: some View {
        ZStack {
            Color("BackgroundTheme")
                .ignoresSafeArea()
                .onTapGesture { isPasswordFocused = false }
            
            VStack(spacing: 0) {
                header
                titleSection
                
                if bluetoothService.wifiNetworks.isEmpty && !isRefreshing {
                    loadingState
                } else {
                    networkList
                }
            }
            
            // Bottom panel when network selected
            if viewModel.selectedWiFiNetwork != nil {
                VStack {
                    Spacer()
                    bottomPanel
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedWiFiNetwork != nil)
        .onAppear {
            // Initial scan
            if bluetoothService.wifiNetworks.isEmpty {
                viewModel.refreshWiFiNetworks()
            }
            
            // Start periodic refresh every 8 seconds
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
                Task { @MainActor in
                    if !viewModel.isConnectingToWiFi {
                        print("🔄 Auto-refreshing WiFi networks...")
                        viewModel.refreshWiFiNetworks()
                    }
                }
            }
        }
        .onDisappear {
            // Stop the timer when leaving the view
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Button {
                if isPasswordFocused { isPasswordFocused = false }
                else { viewModel.goBack() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(Font(UIFont.systemFont(ofSize: 16, weight: .semibold)))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.refreshWiFiNetworks()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Title
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect to WiFi")
                .font(Font(UIFont.systemFont(ofSize: 22, weight: .bold)))
                .foregroundColor(.primary)
            
            Text("Required - enables camera streaming and monitoring")
                .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.3)
            
            Text("Scanning for networks...")
                .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
                .foregroundColor(.secondary)
            
            Text("Make sure you're near your router")
                .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                .foregroundColor(.secondary.opacity(0.7))
            
            Button(action: { viewModel.refreshWiFiNetworks() }) {
                Text("Tap to retry")
                    .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                    .foregroundColor(.green)
            }
            .padding(.top, 20)
            
            Spacer()
        }
    }
    
    // MARK: - Network List
    private var networkList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if isRefreshing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Updating...")
                                .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if !bluetoothService.wifiNetworks.isEmpty {
                        HStack {
                            Text("\(bluetoothService.wifiNetworks.count) networks found")
                                .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                    
                    ForEach(bluetoothService.wifiNetworks) { network in
                        NetworkRow(
                            network: network,
                            isSelected: viewModel.selectedWiFiNetwork?.ssid == network.ssid
                        )
                        .id(network.ssid)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if viewModel.selectedWiFiNetwork?.ssid == network.ssid {
                                    viewModel.selectedWiFiNetwork = nil
                                    viewModel.wifiPassword = ""
                                } else {
                                    viewModel.selectedWiFiNetwork = network
                                    viewModel.wifiPassword = ""
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
                .padding(.bottom, viewModel.selectedWiFiNetwork != nil ? 280 : 40)
            }
            .onChange(of: viewModel.selectedWiFiNetwork) { _, selected in
                if let ssid = selected?.ssid {
                    withAnimation { proxy.scrollTo(ssid, anchor: .center) }
                }
            }
        }
    }
    
    // MARK: - Bottom Panel
    private var bottomPanel: some View {
        VStack(spacing: 16) {
            if let error = viewModel.wifiConnectionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
            }
            
            if let network = viewModel.selectedWiFiNetwork, network.isSecure {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    if showPassword {
                        TextField("Password", text: $viewModel.wifiPassword)
                            .focused($isPasswordFocused)
                            .submitLabel(.join)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                if !viewModel.wifiPassword.isEmpty {
                                    viewModel.connectToSelectedWiFi()
                                }
                            }
                    } else {
                        SecureField("Password", text: $viewModel.wifiPassword)
                            .focused($isPasswordFocused)
                            .submitLabel(.join)
                            .onSubmit {
                                if !viewModel.wifiPassword.isEmpty {
                                    viewModel.connectToSelectedWiFi()
                                }
                            }
                    }
                    
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
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
            }
            
            // Connect button
            Button {
                isPasswordFocused = false
                viewModel.connectToSelectedWiFi()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isConnectingToWiFi {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        Text("Connecting...")
                    } else {
                        Text("Connect")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
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
    
    private var canConnect: Bool {
        guard let network = viewModel.selectedWiFiNetwork else { return false }
        if viewModel.isConnectingToWiFi { return false }
        if network.isSecure && viewModel.wifiPassword.isEmpty { return false }
        return true
    }
}

// MARK: - Network Row
struct NetworkRow: View {
    let network: WiFiNetwork
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: signalIcon)
                .font(Font(UIFont.systemFont(ofSize: 18, weight: .regular)))
                .foregroundColor(isSelected ? .black : .primary)
                .frame(width: 24)
            
            Text(network.ssid)
                .font(Font(UIFont.systemFont(ofSize: 17, weight: .medium)))
                .foregroundColor(isSelected ? .black : .primary)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(network.rssi) dBm")
                .font(Font(UIFont.systemFont(ofSize: 10, weight: .regular)))
                .foregroundColor(isSelected ? .black.opacity(0.6) : .secondary)
            
            if network.isSecure {
                Image(systemName: "lock.fill")
                    .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                    .foregroundColor(isSelected ? .black.opacity(0.6) : .secondary)
            }
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(Font(UIFont.systemFont(ofSize: 14, weight: .bold)))
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
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}
