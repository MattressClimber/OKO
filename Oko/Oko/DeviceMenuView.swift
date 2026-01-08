import SwiftUI

struct DeviceMenuView: View {
    @EnvironmentObject private var manager: SetupManager
    @Binding var showMenu: Bool

    // Persisted theme preference
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some View {
        NavigationStack {
            List {
                devicesSection
                addDeviceSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("OKO")
            .toolbar {
                // Left: optional (you can remove if you want)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { showMenu = false }
                }

                // Right: theme toggle (your button, cleaned up)
                ToolbarItem(placement: .navigationBarTrailing) {
                    themeToggleButton
                }
            }
        }
    }

    // MARK: - Sections

    private var devicesSection: some View {
        Section("My Devices") {
            if manager.devices.isEmpty {
                Text("No devices yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.devices.indices, id: \.self) { index in
                    deviceRow(for: index)
                }
                .onDelete(perform: manager.deleteDevice)
            }
        }
    }

    private var addDeviceSection: some View {
        Section {
            Button {
                showMenu = false
                manager.startNewSetup()
            } label: {
                Label("Add New Device", systemImage: "plus")
            }
        }
    }

    // MARK: - Row

    private func deviceRow(for index: Int) -> some View {
        Button {
            manager.currentDeviceIndex = index
            showMenu = false
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.devices[index].name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(manager.devices[index].type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if index == manager.currentDeviceIndex {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.medium)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Theme Toggle

    private var themeToggleButton: some View {
        Button {
            isDarkMode.toggle()
        } label: {
            Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}
