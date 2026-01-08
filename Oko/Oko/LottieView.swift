import SwiftUI
import Lottie

struct LottieView: UIViewRepresentable {
    var filename: String
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)

        let animationView = LottieAnimationView()
        animationView.animation = LottieAnimation.named(filename)
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = loopMode
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        animationView.play()
        context.coordinator.animationView = animationView
        context.coordinator.currentName = filename

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let animationView = context.coordinator.animationView else { return }

        // Swap animation if the name changed
        if context.coordinator.currentName != filename {
            context.coordinator.currentName = filename
            animationView.stop()
            animationView.animation = LottieAnimation.named(filename)
            animationView.loopMode = loopMode
            animationView.play()
        } else {
            // Ensure it keeps playing if SwiftUI re-renders
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var animationView: LottieAnimationView?
        var currentName: String = ""
    }
}
