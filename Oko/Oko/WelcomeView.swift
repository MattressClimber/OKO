import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var viewModel: SetupFlowViewModel
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    var body: some View {
        ZStack {
            Color("BackgroundTheme")
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                Image("OKOlogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                
                Text("OKO")
                    .font(.okoBrand(size: 90))
                    .foregroundColor(.primary)
                
                Spacer()
                
                VStack(spacing: 15) {
                    Text("Tap anywhere to start setup")
                        .font(Font(UIFont.systemFont(ofSize: 18, weight: .regular)))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Bluetooth access is required to find devices")
                    }
                    .font(Font(UIFont.systemFont(ofSize: 14, weight: .regular)))
                    .foregroundColor(.gray)
                }
                .padding(.bottom, 50)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    viewModel.devSkipForward()
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    Button {
                        isDarkMode.toggle()
                    } label: {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                            .padding(12)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
    }
}


