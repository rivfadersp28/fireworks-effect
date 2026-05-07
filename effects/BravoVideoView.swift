import AVFoundation
import CoreVideo
import SwiftUI

struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    @Binding var framesPerSecond: Int
    var onLuminanceUpdate: ((Double) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(resourceName: resourceName, onLuminanceUpdate: onLuminanceUpdate)
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
        context.coordinator.onLuminanceUpdate = onLuminanceUpdate
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

final class Coordinator: NSObject {
    private let resourceName: String
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var lastLuminanceSampleTime = CACurrentMediaTime()
    var onLuminanceUpdate: ((Double) -> Void)?

    init(resourceName: String, onLuminanceUpdate: ((Double) -> Void)?) {
        self.resourceName = resourceName
        self.onLuminanceUpdate = onLuminanceUpdate
        super.init()
    }

    deinit {
        displayLink?.invalidate()
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
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)

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
        videoOutput = output
        self.player = player
        startLuminanceSamplingIfNeeded()
        player.play()
    }

    @objc private func loopVideo() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func startLuminanceSamplingIfNeeded() {
        guard onLuminanceUpdate != nil, displayLink == nil else {
            return
        }

        let displayLink = CADisplayLink(target: self, selector: #selector(sampleLuminance))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func sampleLuminance() {
        guard onLuminanceUpdate != nil else {
            displayLink?.invalidate()
            displayLink = nil
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastLuminanceSampleTime >= 0.12 else {
            return
        }
        lastLuminanceSampleTime = now

        guard let player,
              let videoOutput,
              let pixelBuffer = videoOutput.copyPixelBuffer(
                forItemTime: player.currentTime(),
                itemTimeForDisplay: nil
              )
        else {
            return
        }

        let luminance = averageLuminance(in: pixelBuffer)
        onLuminanceUpdate?(luminance)
    }

    private func averageLuminance(in pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleColumns = 8
        let sampleRows = 5
        let xStart = Int(Double(width) * 0.24)
        let xEnd = Int(Double(width) * 0.76)
        let yStart = Int(Double(height) * 0.30)
        let yEnd = Int(Double(height) * 0.54)
        var total = 0.0
        var count = 0

        for row in 0..<sampleRows {
            let y = yStart + max((yEnd - yStart) * row / max(sampleRows - 1, 1), 0)
            for column in 0..<sampleColumns {
                let x = xStart + max((xEnd - xStart) * column / max(sampleColumns - 1, 1), 0)
                let offset = y * bytesPerRow + x * 4
                let blue = Double(pixels[offset]) / 255.0
                let green = Double(pixels[offset + 1]) / 255.0
                let red = Double(pixels[offset + 2]) / 255.0
                total += red * 0.2126 + green * 0.7152 + blue * 0.0722
                count += 1
            }
        }

        return count > 0 ? total / Double(count) : 0
    }
}
