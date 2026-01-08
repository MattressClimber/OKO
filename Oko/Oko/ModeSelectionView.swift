import SwiftUI

struct ModeSelectionView: View {
    @EnvironmentObject var manager: SetupManager

    var body: some View {
        ZStack {
            // Dynamic theme background
            Color("BackgroundTheme")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // HEADER
                HStack {
                    Button(action: { manager.goBack() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        // Adaptive so it doesn't disappear in light mode
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                Text("What are we watching?")
                    .font(.title2)
                    .foregroundStyle(.primary)

                HStack(spacing: 20) {
                    // Water Meter
                    Button(action: { manager.selectMode("Water") }) {
                        VStack(spacing: 10) {
                            Image(systemName: "drop.fill")
                                .font(.largeTitle)
                            Text("Water Meter")
                                .font(.headline)
                        }
                        .frame(width: 140, height: 160)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    // Pressure Gauge
                    Button(action: { manager.selectMode("Gauge") }) {
                        VStack(spacing: 10) {
                            Image(systemName: "gauge")
                                .font(.largeTitle)
                            Text("Pressure")
                                .font(.headline)
                        }
                        .frame(width: 140, height: 160)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
    }
}

#Preview {
    ModeSelectionView()
        .environmentObject(SetupManager())
        .background(Color("BackgroundTheme"))
}
