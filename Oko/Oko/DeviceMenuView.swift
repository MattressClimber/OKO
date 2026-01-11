import SwiftUI

struct DeviceMenuView: View {
    @EnvironmentObject var manager: SetupManager
    @Binding var showMenu: Bool
    @State private var showDeleteConfirm = false
    @State private var deviceToDelete: OkoDevice?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color("BackgroundTheme")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Device list
                    if manager.devices.isEmpty {
                        emptyState
                    } else {
                        deviceList
                    }
                    
                    Spacer()
                    
                    // Add device button
                    addDeviceButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showMenu = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert("Delete Device?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let device = deviceToDelete,
                   let index = manager.devices.firstIndex(where: { $0.id == device.id }) {
                    manager.deleteDevice(at: IndexSet(integer: index))
                }
            }
        } message: {
            Text("This will remove \(deviceToDelete?.name ?? "this device") and all its data.")
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Devices")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text("Add your first OKO device to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Device List
    private var deviceList: some View {
        List {
            ForEach(manager.devices) { device in
                DeviceRow(
                    device: device,
                    isSelected: manager.activeDevice?.id == device.id
                )
                .onTapGesture {
                    if let index = manager.devices.firstIndex(where: { $0.id == device.id }) {
                        manager.currentDeviceIndex = index
                        showMenu = false
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deviceToDelete = device
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Add Device Button
    private var addDeviceButton: some View {
        Button(action: {
            showMenu = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                manager.startNewSetup()
            }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add New Device")
            }
            .font(.headline)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.green)
            .cornerRadius(14)
        }
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let device: OkoDevice
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(statusColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text(device.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(device.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var iconName: String {
        switch device.type.lowercased() {
        case "water": return "drop.fill"
        case "gauge": return "gauge"
        default: return "sensor.tag.radiowaves.forward"
        }
    }
    
    private var statusColor: Color {
        switch device.status {
        case .learning: return .orange
        case .ok: return .green
        case .leakDetected: return .red
        case .offline: return .gray
        }
    }
}
