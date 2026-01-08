import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var manager: SetupManager
    
    // Access the same global setting
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    
    var body: some View {
        ZStack {
            // MARK: - BACKGROUND
            Color("BackgroundTheme") // Make sure this is set in Assets!
                .edgesIgnoringSafeArea(.all)
                .animation(.easeInOut, value: isDarkMode)
            
            // MARK: - MAIN CONTENT
            VStack(spacing: 30) {
                Spacer()
                
                Image("OKOlogo") // Make sure this has Any/Dark variants in Assets!
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                
                Text("OKO")
                    .font(.okoBrand(size: 90))
                    .foregroundColor(.primary)
                
                Spacer()
                
                VStack(spacing: 15) {
                    Text("Tap anywhere to start setup")
                        .font(.okoBold(size: 18))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Bluetooth access is required to find devices")
                    }
                    .font(.okoItalic(size: 14))
                    .foregroundColor(.gray)
                }
                .padding(.bottom, 50)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    manager.devSkipForward()
                }
            }
            
            // MARK: - THEME TOGGLE BUTTON
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        // Toggle global state
                        isDarkMode.toggle()
                    }) {
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
        // NOTE: We REMOVED .preferredColorScheme from here because OkoApp handles it now.
    }
}
