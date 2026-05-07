import AVFoundation
import CoreVideo
import MetalKit
import SwiftUI
import simd

struct RippleMetalView: UIViewRepresentable {
    let settings: RippleSettings
    @Binding var framesPerSecond: Int

    func makeCoordinator() -> RippleRenderer {
        RippleRenderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        context.coordinator.configure(for: view)
        context.coordinator.update(settings: settings)
        context.coordinator.onFPSUpdate = { framesPerSecond = $0 }
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(RippleRenderer.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(settings: settings)
        context.coordinator.onFPSUpdate = { framesPerSecond = $0 }
    }
}

final class RippleRenderer: NSObject, MTKViewDelegate {
    private struct Ripple {
        var originAndStartTime: SIMD4<Float>
        var parameters: SIMD4<Float>
    }

    private struct RippleUniforms {
        var resolution: SIMD2<Float>
        var videoSize: SIMD2<Float>
        var time: Float
        var rippleCount: UInt32
        var strength: Float
        var radius: Float
        var speed: Float
        var damping: Float
        var refraction: Float
        var waveCount: Float
        var waveSoftness: Float
        var fadeSpeed: Float
        var waveSpacing: Float
        var glowIntensity: Float
        var glowBrightness: Float
        var padding1: Float
        var padding2: Float
    }

    private let maxRipples = 16
    private let rippleDuration: Float = 2.6
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var lastVideoTexture: MTLTexture?
    private var videoSize = SIMD2<Float>(1, 1)
    private var startTime = CACurrentMediaTime()
    private var lastFPSUpdateTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()
    private var smoothedFPS = 60.0
    private var framesSinceFPSUpdate = 0
    private var ripples: [Ripple] = []
    private var settings = RippleSettings()
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private weak var view: MTKView?
    var onFPSUpdate: ((Int) -> Void)?

    deinit {
        if let playerItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
        }
    }

    func configure(for view: MTKView) {
        self.view = view

        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }

        view.device = device
        self.device = device
        commandQueue = device.makeCommandQueue()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        haptic.prepare()

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "rippleVertex"),
              let fragmentFunction = library.makeFunction(name: "rippleFragment")
        else {
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)

        configureVideoPlayback()
    }

    func update(settings: RippleSettings) {
        self.settings = settings
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view else {
            return
        }

        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else {
            return
        }

        let point = recognizer.location(in: view)
        let now = Float(CACurrentMediaTime() - startTime)
        let normalized = SIMD2<Float>(
            Float(point.x / size.width),
            Float(point.y / size.height)
        )
        playHaptic()
        addRipple(at: normalized, now: now)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandQueue,
              let pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor
        else {
            return
        }

        let now = Float(CACurrentMediaTime() - startTime)
        ripples.removeAll { now - $0.originAndStartTime.z > rippleDuration }
        updateFrameRateEstimate()

        guard let videoTexture = makeCurrentVideoTexture() else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        var uniforms = RippleUniforms(
            resolution: SIMD2<Float>(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            videoSize: videoSize,
            time: now,
            rippleCount: UInt32(ripples.count),
            strength: settings.strength,
            radius: settings.radius,
            speed: settings.speed,
            damping: settings.damping,
            refraction: settings.refraction,
            waveCount: settings.waveCount,
            waveSoftness: settings.waveSoftness,
            fadeSpeed: settings.fadeSpeed,
            waveSpacing: settings.waveSpacing,
            glowIntensity: settings.glowIntensity,
            glowBrightness: settings.glowBrightness,
            padding1: 0,
            padding2: 0
        )

        var rippleBuffer = [Ripple](
            repeating: Ripple(
                originAndStartTime: SIMD4<Float>(0, 0, -100, 0),
                parameters: SIMD4<Float>(0, 0, 0, 0)
            ),
            count: maxRipples
        )
        for index in ripples.indices.prefix(maxRipples) {
            rippleBuffer[index] = ripples[index]
        }

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentTexture(videoTexture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RippleUniforms>.stride, index: 0)
            rippleBuffer.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    encoder.setFragmentBytes(baseAddress, length: bytes.count, index: 1)
                }
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func configureVideoPlayback() {
        guard let url = Bundle.main.url(forResource: "summer", withExtension: "mp4") else {
            return
        }

        let asset = AVURLAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let transformedSize = track.naturalSize.applying(track.preferredTransform)
            videoSize = SIMD2<Float>(
                Float(abs(transformedSize.width)),
                Float(abs(transformedSize.height))
            )
        }

        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
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

        playerItem = item
        videoOutput = output
        self.player = player
        player.play()
    }

    @objc private func loopVideo() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func makeCurrentVideoTexture() -> MTLTexture? {
        guard let videoOutput,
              let textureCache else {
            return nil
        }

        var itemTime = player?.currentTime() ?? .zero
        if !itemTime.isValid {
            itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        }

        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            return lastVideoTexture
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        videoSize = SIMD2<Float>(Float(width), Float(height))

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture)
        else {
            return lastVideoTexture
        }

        lastVideoTexture = texture
        return texture
    }

    private func addRipple(at normalizedPosition: SIMD2<Float>, now: Float) {
        let ripple = Ripple(
            originAndStartTime: SIMD4<Float>(
                normalizedPosition.x,
                normalizedPosition.y,
                now,
                Float.random(in: 0.82...1.18)
            ),
            parameters: SIMD4<Float>(
                settings.strength,
                settings.radius,
                settings.speed,
                settings.damping
            )
        )
        ripples.append(ripple)
        if ripples.count > maxRipples {
            ripples.removeFirst(ripples.count - maxRipples)
        }
    }

    private func playHaptic() {
        if Thread.isMainThread {
            haptic.impactOccurred()
            haptic.prepare()
        } else {
            DispatchQueue.main.async { [haptic] in
                haptic.impactOccurred()
                haptic.prepare()
            }
        }
    }

    private func updateFPS() {
        framesSinceFPSUpdate += 1
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastFPSUpdateTime
        guard elapsed >= 0.2 else {
            return
        }

        let fps = Int(smoothedFPS.rounded())
        lastFPSUpdateTime = currentTime
        framesSinceFPSUpdate = 0

        DispatchQueue.main.async { [weak self] in
            self?.onFPSUpdate?(fps)
        }
    }

    private func updateFrameRateEstimate() {
        let currentTime = CACurrentMediaTime()
        let frameDuration = max(currentTime - lastFrameTime, 1.0 / 240.0)
        lastFrameTime = currentTime

        let instantFPS = 1.0 / frameDuration
        smoothedFPS = smoothedFPS * 0.82 + instantFPS * 0.18
        updateFPS()
    }
}
