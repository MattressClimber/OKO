import SwiftUI

struct ModeSelectionView: View {
    @EnvironmentObject var viewModel: SetupFlowViewModel
    
    var body: some View {
        ZStack {
            Color("BackgroundTheme")
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                HeaderView(title: "Back") {
                    viewModel.goBack()
                }
                
                Spacer()
                
                Text("What are we watching?")
                    .font(Font(UIFont.systemFont(ofSize: 22, weight: .regular)))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 20) {
                    ModeButton(
                        title: OkoDevice.DeviceType.water.rawValue,
                        icon: OkoDevice.DeviceType.water.icon
                    ) {
                        viewModel.selectMode(.water)
                    }
                    
                    ModeButton(
                        title: "Pressure",
                        icon: OkoDevice.DeviceType.gauge.icon
                    ) {
                        viewModel.selectMode(.gauge)
                    }
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - Mode Button

private struct ModeButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(Font(UIFont.systemFont(ofSize: 34, weight: .regular)))
                Text(title)
                    .font(Font(UIFont.systemFont(ofSize: 17, weight: .semibold)))
            }
            .frame(width: 140, height: 160)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header View

private struct HeaderView: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(title)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

