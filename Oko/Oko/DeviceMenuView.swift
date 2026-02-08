import SwiftUI

struct DeviceMenuView: View {
    @EnvironmentObject var setupViewModel: SetupFlowViewModel
    @EnvironmentObject var persistenceService: PersistenceService
    @Binding var showMenu: Bool
    @State private var showDeleteConfirm = false
    @State private var deviceToDelete: OkoDevice?
    
    // Dark mode toggle
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    
    var body: some View {
        NavigationView {
            ZStack {
                Color("BackgroundTheme")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Device list
                    if persistenceService.devices.isEmpty {
                        emptyState
                    } else {
                        deviceList
                    }
                    
                    Spacer()
                    
                    // Settings section
                    settingsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    
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
                   let index = persistenceService.devices.firstIndex(where: { $0.id == device.id }) {
                    persistenceService.deleteDevices(at: IndexSet(integer: index))
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
                .font(Font(UIFont.systemFont(ofSize: 22, weight: .semibold)))
                .foregroundStyle(.primary)
            
            (Text("Add your first ") + 
             Text("OKO").font(.okoBrand(size: 15)) +
             Text(" device to get started"))
                .font(Font(UIFont.systemFont(ofSize: 15, weight: .regular)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Device List
    private var deviceList: some View {
        List {
            ForEach(persistenceService.devices) { device in
                DeviceRow(
                    device: device,
                    isSelected: persistenceService.activeDevice?.id == device.id
                )
                .onTapGesture {
                    if let index = persistenceService.devices.firstIndex(where: { $0.id == device.id }) {
                        persistenceService.currentDeviceIndex = index
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
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(spacing: 12) {
            // Dark mode toggle
            HStack {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isDarkMode ? .purple : .orange)
                    .frame(width: 28)
                
                Text("Dark Mode")
                    .font(Font(UIFont.systemFont(ofSize: 17, weight: .regular)))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Toggle("", isOn: $isDarkMode)
                    .labelsHidden()
                    .tint(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Add Device Button
    private var addDeviceButton: some View {
        Button(action: {
            showMenu = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                setupViewModel.startNewSetup()
            }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add New Device")
            }
            .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
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
                    .font(Font(UIFont.systemFont(ofSize: 17, weight: .medium)))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text(device.type.rawValue)
                        .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(device.status.rawValue.capitalized)
                        .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
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
        device.type.icon
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
