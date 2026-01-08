import SwiftUI
import CoreBluetooth
import Lottie

struct ScanningView: View {
    @EnvironmentObject var manager: SetupManager
    @Environment(\.colorScheme) private var colorScheme

    private var scanningAnimationName: String {
        colorScheme == .dark ? "scanning_eye" : "scanning_eye_dark"
    }

    var body: some View {
        ZStack {
            // Dynamic theme background from Assets
            Color("BackgroundTheme")
                .ignoresSafeArea()

            VStack {
                // MARK: - Header
                HStack {
                    Button(action: { manager.goBack() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back").font(.okoBold(size: 16))
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if manager.bleManager.isConnected {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                    }
                }
                .padding()

                Spacer()

                // MARK: - MAIN CONTENT
                if manager.bleManager.discoveredDevices.isEmpty {
                    VStack(spacing: 20) {
                        LottieView(filename: scanningAnimationName)
                            .frame(width: 250, height: 250)
                            .id(scanningAnimationName) // keep this if you want a guaranteed swap

                        HStack(spacing: 0) {
                            Text("Searching for ")
                                .font(.okoBold(size: 24))
                            Text("OKO")
                                .font(.okoBrand(size: 24))
                            Text("...")
                                .font(.okoBold(size: 24))
                        }
                        .foregroundStyle(.primary)

                        Text("Looking for \(manager.tempSelectedMode) Device")
                            .font(.okoItalic(size: 14))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Devices Found")
                            .font(.okoBold(size: 18))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)

                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(manager.bleManager.discoveredDevices, id: \.identifier) { device in
                                    Button(action: {
                                        manager.userDidSelectDevice(device)
                                    }) {
                                        HStack {
                                            Image(systemName: "sensor.tag.fill")
                                                .foregroundStyle(.green)
                                                .font(.title2)

                                            VStack(alignment: .leading) {
                                                Text(device.name ?? "Unknown Device")
                                                    .font(.okoBold(size: 16))
                                                    .foregroundStyle(.primary)

                                                Text(device.identifier.uuidString.prefix(8))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Text("Connect")
                                                .font(.okoBold(size: 14))
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
                            .padding(.horizontal, 20)
                        }
                        .frame(maxHeight: 350)
                    }
                    .transition(.opacity)
                }

                Spacer()
            }
        }
        .onAppear { manager.bleManager.startScanning() }
        .onDisappear {
            if !manager.bleManager.isConnected {
                manager.bleManager.stopScanning()
            }
        }
    }
}
