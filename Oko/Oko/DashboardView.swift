import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var setupViewModel: SetupFlowViewModel
    @EnvironmentObject var persistenceService: PersistenceService
    @EnvironmentObject var bluetoothService: BluetoothService
    @State private var showDeviceMenu = false

    // MARK: - Learning Phase Logic
    var learningProgress: String {
        guard let device = persistenceService.activeDevice else { return "" }
        let hoursPassed = Date().timeIntervalSince(device.installDate) / 3600
        let hoursTotal = 72.0

        if hoursPassed < hoursTotal {
            let remaining = Int(hoursTotal - hoursPassed)
            return "\(remaining)h remaining"
        }
        return "Complete"
    }

    // MARK: - Battery Helpers
    private func batteryPercent(for device: OkoDevice) -> Int {
        return device.batteryPercent
    }

    private func batterySymbol(for percent: Int) -> String {
        switch percent {
        case 0...10: return "battery.0"
        case 11...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(for percent: Int) -> Color {
        switch percent {
        case 0...15: return .red
        case 16...35: return .orange
        default: return .green
        }
    }

    var body: some View {
        ZStack {
            // MARK: - Dynamic Background
            Color("BackgroundTheme")
                .ignoresSafeArea()

            if let device = persistenceService.activeDevice {
                VStack(spacing: 0) {

                    // MARK: - Header
                    HStack {
                        Button(action: { showDeviceMenu = true }) {
                            Image(systemName: "line.3.horizontal")
                                .font(Font(UIFont.systemFont(ofSize: 22, weight: .regular)))
                                .foregroundStyle(Color.primary)
                                .accessibilityLabel("Menu")
                        }

                        Spacer()
                        
                        // Sync status
                        if bluetoothService.isConnected {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()

                    ScrollView {
                        VStack(spacing: 25) {

                            StatusBanner(
                                status: device.status,
                                learningTime: learningProgress
                            )

                            // MARK: - Main Reading
                            VStack(spacing: 10) {
                                // Device name
                                Text(device.name)
                                    .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
                                    .foregroundStyle(.secondary)

                                // Battery indicator
                                let pct = batteryPercent(for: device)
                                HStack(spacing: 8) {
                                    Image(systemName: batterySymbol(for: pct))
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(batteryColor(for: pct))

                                    Text("\(pct)%")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }

                                // Reading display
                                if device.status == .learning {
                                    Text("---")
                                        .font(Font(UIFont.systemFont(ofSize: 60, weight: .bold)))
                                        .foregroundStyle(.secondary)

                                    Text("Establishing Baseline...")
                                        .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(device.lastReading)
                                        .font(Font(UIFont.systemFont(ofSize: 50, weight: .bold)))
                                        .foregroundStyle(.primary)
                                    
                                    // Last update time
                                    Text("Last updated: \(formatDate(device.installDate))")
                                        .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 20)

                            // MARK: - Stats Cards
                            HStack(spacing: 15) {
                                StatCard(
                                    title: "Today",
                                    value: "0 L",
                                    icon: "drop.fill",
                                    color: .blue
                                )
                                
                                StatCard(
                                    title: "This Week",
                                    value: "0 L",
                                    icon: "calendar",
                                    color: .green
                                )
                            }
                            .padding(.horizontal)

                            // MARK: - Chart Placeholder
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Usage History")
                                    .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
                                    .foregroundStyle(.primary)
                                
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(height: 200)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "chart.line.uptrend.xyaxis")
                                                .font(Font(UIFont.systemFont(ofSize: 34, weight: .regular)))
                                                .foregroundStyle(.secondary)
                                            Text("Data will appear after baseline")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    )
                            }
                            .padding(.horizontal)

                            // MARK: - Device Info Card
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Device Info")
                                    .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
                                    .foregroundStyle(.primary)
                                
                                VStack(spacing: 0) {
                                    InfoRow(label: "Type", value: device.type.rawValue)
                                    Divider()
                                    InfoRow(label: "Installed", value: formatDate(device.installDate))
                                    Divider()
                                    InfoRow(label: "Status", value: device.status.rawValue.capitalized)
                                    if let status = bluetoothService.deviceStatus {
                                        Divider()
                                        InfoRow(label: "Photos Taken", value: "\(status.photos ?? 0)")
                                        Divider()
                                        InfoRow(label: "Firmware", value: status.version ?? "Unknown")
                                    }
                                }
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)

                            Spacer(minLength: 50)
                        }
                        .padding(.top)
                    }
                }
            } else {
                // No devices
                VStack(spacing: 12) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(Font(UIFont.systemFont(ofSize: 60, weight: .regular)))
                        .foregroundStyle(.secondary)
                    
                    Text("No Devices Found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Button(action: { setupViewModel.startNewSetup() }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Device")
                        }
                        .fontWeight(.semibold)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .sheet(isPresented: $showDeviceMenu) {
            DeviceMenuView(showMenu: $showDeviceMenu)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Status Banner View
struct StatusBanner: View {
    var status: OkoDevice.DeviceStatus
    var learningTime: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(Font(UIFont.systemFont(ofSize: 20, weight: .regular)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                }
            }

            Spacer()
        }
        .padding()
        .foregroundStyle(statusColor)
        .background(statusColor.opacity(0.15))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var iconName: String {
        switch status {
        case .learning: return "hourglass"
        case .ok: return "checkmark.circle.fill"
        case .leakDetected: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    private var title: String {
        switch status {
        case .learning: return "Learning Baseline"
        case .ok: return "Everything is currently okay."
        case .leakDetected: return "Problem Detected!"
        case .offline: return "Device Offline"
        }
    }

    private var subtitle: String? {
        if status == .learning {
            return "AI is analyzing usage patterns. \(learningTime)"
        }
        return nil
    }

    private var statusColor: Color {
        switch status {
        case .learning: return .orange
        case .ok: return .green
        case .leakDetected: return .red
        case .offline: return .gray
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(Font(UIFont.systemFont(ofSize: 22, weight: .bold)))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
