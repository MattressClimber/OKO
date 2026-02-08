import SwiftUI
import CoreBluetooth

// MARK: - Scanning View

struct ScanningView: View {
    @EnvironmentObject var viewModel: SetupFlowViewModel
    @EnvironmentObject var bluetoothService: BluetoothService
    @Environment(\.colorScheme) private var colorScheme
    
    private var scanningAnimationName: String {
        colorScheme == .dark ? "scanning_eye" : "scanning_eye_dark"
    }
    
    var body: some View {
        ZStack {
            Color("BackgroundTheme")
                .ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Button {
                        viewModel.goBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                                .font(Font(UIFont.systemFont(ofSize: 16, weight: .regular)))
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if bluetoothService.isConnected {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                    }
                }
                .padding()
                
                Spacer()
                
                // Main content
                if bluetoothService.discoveredDevices.isEmpty {
                    searchingState
                } else {
                    devicesFoundList
                }
                
                Spacer()
            }
        }
        .onAppear {
            bluetoothService.startScanning()
        }
        .onDisappear {
            if !bluetoothService.isConnected {
                bluetoothService.stopScanning()
            }
        }
    }
    
    // MARK: - Searching State
    
    private var searchingState: some View {
        VStack(spacing: 20) {
            LottieView(filename: scanningAnimationName)
                .frame(width: 250, height: 250)
                .id(scanningAnimationName)
            
            HStack(spacing: 0) {
                Text("Searching for ")
                    .font(Font(UIFont.systemFont(ofSize: 24, weight: .regular)))
                Text("OKO")
                    .font(.okoBrand(size: 24))
                Text("...")
                    .font(Font(UIFont.systemFont(ofSize: 24, weight: .regular)))
            }
            .foregroundStyle(.primary)
            
            Text("Looking for \(viewModel.selectedMode.rawValue) Device")
                .font(Font(UIFont.systemFont(ofSize: 14, weight: .regular)))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Devices Found List
    
    private var devicesFoundList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Devices Found")
                .font(Font(UIFont.systemFont(ofSize: 18, weight: .regular)))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(bluetoothService.discoveredDevices, id: \.identifier) { device in
                        DeviceListItem(device: device) {
                            viewModel.connectToDevice(device)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 350)
        }
        .transition(.opacity)
    }
}
// MARK: - Device List Item

private struct DeviceListItem: View {
    let device: CBPeripheral
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "sensor.tag.fill")
                    .foregroundStyle(.green)
                    .font(Font(UIFont.systemFont(ofSize: 22, weight: .regular)))
                
                VStack(alignment: .leading) {
                    Text(device.name ?? "Unknown Device")
                        .font(Font(UIFont.systemFont(ofSize: 16, weight: .regular)))
                        .foregroundStyle(.primary)
                    
                    Text(device.identifier.uuidString.prefix(8))
                        .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("Connect")
                    .font(Font(UIFont.systemFont(ofSize: 14, weight: .regular)))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

