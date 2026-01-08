import SwiftUI

struct LabelInputView: View {
    @EnvironmentObject var manager: SetupManager

    var body: some View {
        ZStack {
            // Dynamic theme background
            Color("BackgroundTheme")
                .ignoresSafeArea()

            VStack {
                // MARK: - Header
                HStack {
                    Button(action: { manager.goBack() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        // Adaptive color for light/dark
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                // MARK: - Content
                // Single title with mixed fonts (no duplicate text)
                HStack(spacing: 0) {
                    Text("Name your ")
                        .font(.okoBold(size: 28))
                    Text("OKO")
                        .font(.okoBrand(size: 28))
                }
                .foregroundStyle(.primary)

                Text("Where is this device located?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)

                // Text Input
                TextField("e.g. Basement Main", text: $manager.tempDeviceLabel)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)

                // Next Button
                Button(action: { manager.submitLabel() }) {
                    Text("Next")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            manager.tempDeviceLabel.isEmpty
                            ? Color.gray.opacity(0.5)
                            : Color.green
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(manager.tempDeviceLabel.isEmpty)
                .padding(.horizontal, 40)
                .padding(.top, 20)

                Spacer()
            }
        }
    }
}
