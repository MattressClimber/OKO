import SwiftUI

struct LabelInputView: View {
    @EnvironmentObject var viewModel: SetupFlowViewModel
    
    var body: some View {
        ZStack {
            Color("BackgroundTheme")
                .ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Button(action: { viewModel.goBack() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Title
                HStack(spacing: 0) {
                    Text("Name your ")
                        .font(Font(UIFont.systemFont(ofSize: 28, weight: .regular)))
                    Text("OKO")
                        .font(.okoBrand(size: 28))
                }
                .foregroundStyle(.primary)
                
                Text("Where is this device located?")
                    .font(Font(UIFont.systemFont(ofSize: 12, weight: .regular)))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
                
                // Input field
                TextField("e.g. Basement Main", text: $viewModel.deviceLabel)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
                    .submitLabel(.next)
                    .onSubmit {
                        if !viewModel.deviceLabel.isEmpty {
                            viewModel.submitLabel()
                        }
                    }
                
                // Next button
                Button {
                    viewModel.submitLabel()
                } label: {
                    Text("Next")
                        .font(Font(UIFont.systemFont(ofSize: 17, weight: .bold)))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            viewModel.deviceLabel.isEmpty
                            ? Color.gray.opacity(0.5)
                            : Color.green
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.deviceLabel.isEmpty)
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                Spacer()
            }
        }
    }
}
