import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var manager: SetupManager
    @State private var showDeviceMenu = false

    // MARK: - Learning Phase Logic
    var learningProgress: String {
        guard let device = manager.activeDevice else { return "" }
        let hoursPassed = Date().timeIntervalSince(device.installDate) / 3600
        let hoursTotal = 72.0

        if hoursPassed < hoursTotal {
            let remaining = Int(hoursTotal - hoursPassed)
            return "\(remaining)h remaining"
        }
        return "Complete"
    }

    // MARK: - Battery Helpers
    // ⚠️ Replace once real battery data exists
    private func batteryPercent(for device: OkoDevice) -> Int {
        return 100
        // Examples:
        // return device.batteryPercent
        // return Int(device.batteryLevel * 100)
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
            // MARK: - Dynamic Background (Asset)
            Color("BackgroundTheme")
                .ignoresSafeArea()

            if let device = manager.activeDevice {
                VStack(spacing: 0) {

                    // MARK: - Header
                    HStack {
                        Button(action: { showDeviceMenu = true }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                // Key change: adaptive foreground that stays visible in light/dark
                                .foregroundStyle(Color.primary)
                                .accessibilityLabel("Menu")
                        }

                        Spacer()
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
                                // oko / device name
                                Text(device.name)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                // Battery BELOW oko text
                                let pct = batteryPercent(for: device)
                                HStack(spacing: 8) {
                                    Image(systemName: batterySymbol(for: pct))
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(batteryColor(for: pct))

                                    Text("\(pct)%")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }

                                // Reading
                                if device.status == .learning {
                                    Text("---")
                                        .font(.system(size: 60, weight: .bold))
                                        .foregroundStyle(.secondary)

                                    Text("Establishing Baseline...")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("124,503 L")
                                        .font(.system(size: 50, weight: .bold))
                                        // was .white; this now adapts so it won't vanish in light mode
                                        .foregroundStyle(.primary)
                                }
                            }
                            .padding(.top, 20)

                            // MARK: - Chart Placeholder
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 200)
                                .overlay(
                                    Text("Usage History")
                                        .foregroundStyle(.secondary)
                                )

                            Spacer()
                        }
                        .padding()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("No Devices Found")
                        .foregroundStyle(.secondary)
                    Button("Add Device") {
                        manager.startNewSetup()
                    }
                }
            }
        }
        .sheet(isPresented: $showDeviceMenu) {
            DeviceMenuView(showMenu: $showDeviceMenu)
        }
    }
}

// MARK: - Status Banner View
struct StatusBanner: View {
    var status: OkoDevice.DeviceStatus
    var learningTime: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
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
