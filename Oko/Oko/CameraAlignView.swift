import SwiftUI

struct CameraAlignView: View {
    @EnvironmentObject var manager: SetupManager

    // Auto-Flash State (currently not used elsewhere, kept for your logic)
    @State private var isFlashOn = false

    // Physical target box (points)
    let boxWidth: CGFloat = 300
    let boxHeight: CGFloat = 150

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dynamic theme background (behind everything)
                Color("BackgroundTheme")
                    .ignoresSafeArea()

                // 1) VIDEO FEED CONTAINER (4:3)
                ZStack {
                    // Placeholder for MJPEG Stream
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.gray.opacity(0.18))
                        .overlay(
                            // 2) Dark mask with cutout window
                            Color.black.opacity(0.65)
                                .mask(
                                    ZStack {
                                        Rectangle().fill(Color.white)
                                        RoundedRectangle(cornerRadius: 6)
                                            .frame(width: boxWidth, height: boxHeight)
                                            .blendMode(.destinationOut)
                                    }
                                    .compositingGroup()
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4/3, contentMode: .fit) // CRITICAL: Matches ESP32 Sensor
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // 3) UI OVERLAY
                VStack {
                    header

                    Spacer()

                    guideBox

                    Spacer()

                    confirmButton(geometry: geometry)
                }
                .padding(.top, 12)
            }
        }
        .onAppear { isFlashOn = true }
        .onDisappear { isFlashOn = false }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Button(action: { manager.goBack() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18) // safer across devices without hardcoding 50
    }

    // MARK: - Guide Box
    private var guideBox: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.green, lineWidth: 2)
            .frame(width: boxWidth, height: boxHeight)
            .overlay(alignment: .top) {
                Text("Align digits inside the box")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                    .offset(y: -34)
            }
    }

    // MARK: - Confirm Button
    private func confirmButton(geometry: GeometryProxy) -> some View {
        Button(action: {
            // --- KEEPING YOUR ROI MATH EXACTLY ---
            let screenW = geometry.size.width
            let videoH = screenW * (3/4) // 4:3 aspect ratio height

            let percentW = boxWidth / screenW
            let percentH = boxHeight / videoH

            // centered ROI
            let startX = (1.0 - percentW) / 2.0
            let startY = (1.0 - percentH) / 2.0

            manager.saveROI(x: startX, y: startY, w: percentW, h: percentH)
        }) {
            Text("It Looks Good")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }
}
