import AVFoundation
import SwiftUI

struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    @Binding var framesPerSecond: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(resourceName: resourceName)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.configure(playerLayer: view.playerLayer)

        DispatchQueue.main.async {
            framesPerSecond = 0
        }

        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

final class Coordinator {
    private let resourceName: String
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?

    init(resourceName: String) {
        self.resourceName = resourceName
    }

    deinit {
        if let playerItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
        }
    }

    func configure(playerLayer: AVPlayerLayer) {
        guard player == nil,
              let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4")
        else {
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.isMuted = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopVideo),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        playerLayer.player = player
        playerItem = item
        self.player = player
        player.play()
    }

    @objc private func loopVideo() {
        player?.seek(to: .zero)
        player?.play()
    }
}
