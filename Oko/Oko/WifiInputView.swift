import SwiftUI

struct WifiInputView: View {
    @EnvironmentObject var manager: SetupManager
    
    // Local State
    @State private var password = ""
    @State private var selectedNetwork: String? = nil
    @FocusState private var isPasswordFocused: Bool
    
    // Mock Data
    let networks = [
        ("Home_WiFi_5G", true),
        ("Guest_Network", false),
        ("Office_Basement", true),
        ("Linksys_Legacy", true),
        ("Neighbor_Slow", true),
        ("Hidden_Network", true)
    ]
    
    var body: some View {
        ZStack {
            // MARK: - BACKGROUND
            Color("BackgroundTheme")
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    isPasswordFocused = false
                }
            
            // MARK: - MAIN CONTENT
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        if isPasswordFocused {
                            isPasswordFocused = false
                        } else {
                            manager.goBack()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.okoBold(size: 16))
                        .foregroundColor(.secondary)
                        .padding()
                    }
                    Spacer()
                }
                
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Network")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Choose a 2.4GHz network for better range.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 25)
                .padding(.bottom, 20)
                
                // Network List
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(networks, id: \.0) { network in
                                NetworkRow(
                                    name: network.0,
                                    isLocked: network.1,
                                    isSelected: selectedNetwork == network.0
                                )
                                .id(network.0) // For scrolling to
                                .onTapGesture {
                                    selectionHaptic()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        selectedNetwork = network.0
                                        password = ""
                                        isPasswordFocused = true // Auto-focus
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        // Dynamic padding: If panel is up, add extra space so list isn't hidden
                        .padding(.bottom, selectedNetwork != nil ? 250 : 20)
                    }
                    .onChange(of: isPasswordFocused) { focused in
                        // If keyboard comes up and we have a selection, scroll to it
                        if focused, let selected = selectedNetwork {
                            withAnimation {
                                scrollProxy.scrollTo(selected, anchor: .center)
                            }
                        }
                    }
                }
            }
            
            // MARK: - BOTTOM ACTION PANEL
            // By placing this in a ZStack aligned to bottom, it will sit on top of the list.
            // Because we DO NOT ignore the keyboard safe area, the system moves the "bottom"
            // of this view up when the keyboard appears.
            VStack {
                Spacer() // Pushes the panel to the bottom
                
                if let selected = selectedNetwork {
                    VStack(spacing: 20) {
                        // Password Field
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.secondary)
                            
                            if #available(iOS 15.0, *) {
                                SecureField("Password for \(selected)", text: $password)
                                    .focused($isPasswordFocused)
                                    .submitLabel(.join)
                                    .onSubmit {
                                        if !password.isEmpty { manager.devSkipForward() }
                                    }
                            } else {
                                SecureField("Password for \(selected)", text: $password)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isPasswordFocused ? Color.green : Color.clear, lineWidth: 1)
                        )
                        
                        // Connect Button
                        Button(action: {
                            isPasswordFocused = false
                            manager.devSkipForward()
                        }) {
                            HStack {
                                Text("Connect Device")
                                    .fontWeight(.bold)
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(password.isEmpty ? Color.gray.opacity(0.3) : Color.green)
                            .foregroundColor(password.isEmpty ? .secondary : .black)
                            .cornerRadius(12)
                        }
                        .disabled(password.isEmpty)
                    }
                    .padding(25)
                    .background(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 25, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 25))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // NOTE: No .ignoresSafeArea(.keyboard) here.
        // This allows the ZStack bounds to shrink when keyboard appears.
    }
    
    private func selectionHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// Keeping the helper shape and subview consistent
struct NetworkRow: View {
    let name: String
    let isLocked: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "wifi")
                .foregroundColor(isSelected ? .black : .primary)
            Text(name)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .black : .primary)
            Spacer()
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(isSelected ? .black.opacity(0.6) : .secondary)
            }
        }
        .padding()
        .background(isSelected ? Color.green : Color(UIColor.systemGray6))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isLocked ? "Secure" : "Open") network")
        .accessibilityAddTraits(isSelected ? .isSelected : .isButton)
    }
}

struct UnevenRoundedRectangle: Shape {
    var topLeadingRadius: CGFloat
    var bottomLeadingRadius: CGFloat
    var bottomTrailingRadius: CGFloat
    var topTrailingRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [
                topLeadingRadius > 0 ? .topLeft : [],
                topTrailingRadius > 0 ? .topRight : [],
                bottomLeadingRadius > 0 ? .bottomLeft : [],
                bottomTrailingRadius > 0 ? .bottomRight : []
            ].reduce(into: UIRectCorner()) { $0.insert($1) },
            cornerRadii: CGSize(width: topLeadingRadius, height: topLeadingRadius)
        )
        return Path(path.cgPath)
    }
}
