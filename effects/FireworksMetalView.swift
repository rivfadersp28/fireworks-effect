import MetalKit
import SwiftUI
import simd

struct FireworksMetalView: UIViewRepresentable {
    let settings: FireworksSettings
    @Binding var framesPerSecond: Int

    func makeCoordinator() -> Renderer {
        Renderer()
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
        context.coordinator.onFPSUpdate = { framesPerSecond = $0 }
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Renderer.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(settings: settings)
        context.coordinator.onFPSUpdate = { framesPerSecond = $0 }
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    private struct Firework {
        var base: SIMD4<Float>
        var fade: SIMD4<Float>

        var startTime: Float {
            base.z
        }

        var isFadingOut: Bool {
            fade.x >= 0
        }
    }

    private struct FrameUniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var fireworkCount: UInt32
        var explosionRadius: Float
        var particleSize: Float
        var glowIntensity: Float
        var glowRadius: Float
        var particleBlur: Float
        var fadeSpeed: Float
        var flightSpeed: Float
        var gravity: Float
        var trailBrightness: Float
        var trailLength: Float
        var activeParticleCount: Float
        var padding1: Float
        var padding2: Float
        var padding3: Float
    }

    private struct BloomUniforms {
        var texelSize: SIMD2<Float>
        var direction: SIMD2<Float>
        var threshold: Float
        var intensity: Float
    }

    private let maxFireworks = 64
    private let particlesPerFirework = 100
    private let trailCurveSegments = 6
    private let forcedFadeDuration: Float = 0.3
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var particlePipelineState: MTLRenderPipelineState?
    private var trailPipelineState: MTLRenderPipelineState?
    private var bloomExtractPipelineState: MTLRenderPipelineState?
    private var bloomBlurPipelineState: MTLRenderPipelineState?
    private var toneMapPipelineState: MTLRenderPipelineState?
    private var accumulationTexture: MTLTexture?
    private var bloomTextureA: MTLTexture?
    private var bloomTextureB: MTLTexture?
    private var startTime = CACurrentMediaTime()
    private var lastFPSUpdateTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()
    private var lastAutomaticFireworkTime: Float = 0
    private var smoothedFPS = 60.0
    private var framesSinceFPSUpdate = 0
    private var fireworks: [Firework] = []
    private var settings = FireworksSettings()
    private let explosionHaptic = UIImpactFeedbackGenerator(style: .light)
    private weak var view: MTKView?
    var onFPSUpdate: ((Int) -> Void)?

    func configure(for view: MTKView) {
        self.view = view

        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }

        view.device = device
        self.device = device
        commandQueue = device.makeCommandQueue()
        explosionHaptic.prepare()

        guard let library = device.makeDefaultLibrary(),
              let particleVertex = library.makeFunction(name: "fireworksParticleVertex"),
              let particleFragment = library.makeFunction(name: "fireworksParticleFragment"),
              let trailVertex = library.makeFunction(name: "fireworksTrailVertex"),
              let trailFragment = library.makeFunction(name: "fireworksTrailFragment"),
              let bloomExtractFragment = library.makeFunction(name: "bloomExtractFragment"),
              let bloomBlurFragment = library.makeFunction(name: "bloomBlurFragment"),
              let toneMapVertex = library.makeFunction(name: "toneMapVertex"),
              let toneMapFragment = library.makeFunction(name: "toneMapFragment")
        else {
            return
        }

        let particleDescriptor = MTLRenderPipelineDescriptor()
        particleDescriptor.vertexFunction = particleVertex
        particleDescriptor.fragmentFunction = particleFragment
        particleDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        particleDescriptor.colorAttachments[0].isBlendingEnabled = true
        particleDescriptor.colorAttachments[0].rgbBlendOperation = .add
        particleDescriptor.colorAttachments[0].alphaBlendOperation = .add
        particleDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        particleDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        let trailDescriptor = MTLRenderPipelineDescriptor()
        trailDescriptor.vertexFunction = trailVertex
        trailDescriptor.fragmentFunction = trailFragment
        trailDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        trailDescriptor.colorAttachments[0].isBlendingEnabled = true
        trailDescriptor.colorAttachments[0].rgbBlendOperation = .add
        trailDescriptor.colorAttachments[0].alphaBlendOperation = .add
        trailDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        trailDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        trailDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        trailDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        let toneMapDescriptor = MTLRenderPipelineDescriptor()
        toneMapDescriptor.vertexFunction = toneMapVertex
        toneMapDescriptor.fragmentFunction = toneMapFragment
        toneMapDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        let bloomExtractDescriptor = MTLRenderPipelineDescriptor()
        bloomExtractDescriptor.vertexFunction = toneMapVertex
        bloomExtractDescriptor.fragmentFunction = bloomExtractFragment
        bloomExtractDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        let bloomBlurDescriptor = MTLRenderPipelineDescriptor()
        bloomBlurDescriptor.vertexFunction = toneMapVertex
        bloomBlurDescriptor.fragmentFunction = bloomBlurFragment
        bloomBlurDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        particlePipelineState = try? device.makeRenderPipelineState(descriptor: particleDescriptor)
        trailPipelineState = try? device.makeRenderPipelineState(descriptor: trailDescriptor)
        bloomExtractPipelineState = try? device.makeRenderPipelineState(descriptor: bloomExtractDescriptor)
        bloomBlurPipelineState = try? device.makeRenderPipelineState(descriptor: bloomBlurDescriptor)
        toneMapPipelineState = try? device.makeRenderPipelineState(descriptor: toneMapDescriptor)
    }

    func update(settings: FireworksSettings) {
        self.settings = settings
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view else {
            return
        }

        let point = recognizer.location(in: view)
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else {
            return
        }

        let normalized = SIMD2<Float>(
            Float(point.x / size.width),
            Float(point.y / size.height)
        )
        let now = Float(CACurrentMediaTime() - startTime)
        spawnFirework(at: normalized, now: now)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        accumulationTexture = nil
        bloomTextureA = nil
        bloomTextureB = nil
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandQueue,
              let particlePipelineState,
              let trailPipelineState,
              let bloomExtractPipelineState,
              let bloomBlurPipelineState,
              let toneMapPipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let now = Float(CACurrentMediaTime() - startTime)
        spawnAutomaticFireworkIfNeeded(now: now)
        fireworks.removeAll { firework in
            if firework.isFadingOut {
                return now - firework.fade.x >= forcedFadeDuration
            }

            return now - firework.startTime > 3.4
        }
        enforceVisibleParticleBudget(now: now)
        updateFrameRateEstimate()

        guard let accumulationTexture = makeAccumulationTexture(for: view) else {
            return
        }
        guard let bloomTextures = makeBloomTextures(for: view) else {
            return
        }
        let bloomTextureA = bloomTextures.0
        let bloomTextureB = bloomTextures.1

        var uniforms = FrameUniforms(
            resolution: SIMD2<Float>(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            time: now,
            fireworkCount: UInt32(fireworks.count),
            explosionRadius: settings.explosionRadius,
            particleSize: settings.particleSize,
            glowIntensity: settings.glowIntensity,
            glowRadius: settings.glowRadius,
            particleBlur: settings.particleBlur,
            fadeSpeed: settings.fadeSpeed,
            flightSpeed: settings.flightSpeed,
            gravity: settings.gravity,
            trailBrightness: settings.trailBrightness,
            trailLength: settings.trailLength,
            activeParticleCount: Float(particlesPerFirework),
            padding1: 0,
            padding2: 0,
            padding3: 0
        )

        let particlePassDescriptor = MTLRenderPassDescriptor()
        particlePassDescriptor.colorAttachments[0].texture = accumulationTexture
        particlePassDescriptor.colorAttachments[0].loadAction = .clear
        particlePassDescriptor.colorAttachments[0].storeAction = .store
        particlePassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: particlePassDescriptor) {
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)

            fireworks.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress, !fireworks.isEmpty {
                    encoder.setVertexBytes(baseAddress, length: bytes.count, index: 1)
                    encoder.setRenderPipelineState(trailPipelineState)
                    encoder.drawPrimitives(
                        type: .triangle,
                        vertexStart: 0,
                        vertexCount: fireworks.count * particlesPerFirework * trailCurveSegments * 6
                    )

                    encoder.setRenderPipelineState(particlePipelineState)
                    encoder.drawPrimitives(
                        type: .point,
                        vertexStart: 0,
                        vertexCount: fireworks.count * particlesPerFirework
                    )
                }
            }

            encoder.endEncoding()
        }

        renderBloom(
            commandBuffer: commandBuffer,
            sourceTexture: accumulationTexture,
            bloomTextureA: bloomTextureA,
            bloomTextureB: bloomTextureB,
            extractPipelineState: bloomExtractPipelineState,
            blurPipelineState: bloomBlurPipelineState
        )

        if let renderPassDescriptor = view.currentRenderPassDescriptor,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.setRenderPipelineState(toneMapPipelineState)
            encoder.setFragmentTexture(accumulationTexture, index: 0)
            encoder.setFragmentTexture(bloomTextureA, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
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

    private func spawnAutomaticFireworkIfNeeded(now: Float) {
        guard now - lastAutomaticFireworkTime >= 1 else {
            return
        }

        lastAutomaticFireworkTime = now
        spawnFirework(
            at: SIMD2<Float>(
                Float.random(in: 0.12...0.88),
                Float.random(in: 0.16...0.78)
            ),
            now: now
        )
    }

    private func spawnFirework(at normalizedPosition: SIMD2<Float>, now: Float) {
        playExplosionHaptic()
        let seed = Float.random(in: 1...10_000)
        fireworks.append(
            Firework(
                base: SIMD4<Float>(normalizedPosition.x, normalizedPosition.y, now, seed),
                fade: SIMD4<Float>(-1, 0, 0, 0)
            )
        )
        enforceStoredFireworkLimit(now: now)
        enforceVisibleParticleBudget(now: now)
    }

    private func playExplosionHaptic() {
        if Thread.isMainThread {
            explosionHaptic.impactOccurred(intensity: 0.65)
            explosionHaptic.prepare()
        } else {
            DispatchQueue.main.async { [explosionHaptic] in
                explosionHaptic.impactOccurred(intensity: 0.65)
                explosionHaptic.prepare()
            }
        }
    }

    private func enforceStoredFireworkLimit(now: Float) {
        guard fireworks.count > maxFireworks else {
            return
        }

        let overflowCount = fireworks.count - maxFireworks
        for index in fireworks.indices.prefix(overflowCount) where !fireworks[index].isFadingOut {
            fireworks[index].fade.x = now
        }
    }

    private func enforceVisibleParticleBudget(now: Float) {
        let verticesPerFirework = particlesPerFirework * (1 + trailCurveSegments * 6)
        let instancesPerFirework = verticesPerFirework
        guard instancesPerFirework > 0 else {
            return
        }

        let maxVisibleParticleInstances = max(instancesPerFirework, Int(settings.maxVisibleParticleInstances.rounded()))
        let maxVisibleFireworks = max(1, maxVisibleParticleInstances / instancesPerFirework)
        let activeFireworkCount = fireworks.filter { !$0.isFadingOut }.count
        let overflowCount = activeFireworkCount - maxVisibleFireworks
        guard overflowCount > 0 else {
            return
        }

        var remainingOverflow = overflowCount
        for index in fireworks.indices where remainingOverflow > 0 && !fireworks[index].isFadingOut {
            fireworks[index].fade.x = now
            remainingOverflow -= 1
        }
    }

    private func makeAccumulationTexture(for view: MTKView) -> MTLTexture? {
        guard let device else {
            return nil
        }

        let width = max(Int(view.drawableSize.width), 1)
        let height = max(Int(view.drawableSize.height), 1)
        if let accumulationTexture,
           accumulationTexture.width == width,
           accumulationTexture.height == height {
            return accumulationTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        accumulationTexture = device.makeTexture(descriptor: descriptor)
        return accumulationTexture
    }

    private func makeBloomTextures(for view: MTKView) -> (MTLTexture, MTLTexture)? {
        guard let device else {
            return nil
        }

        let width = max(Int(view.drawableSize.width) / 2, 1)
        let height = max(Int(view.drawableSize.height) / 2, 1)
        if let bloomTextureA,
           let bloomTextureB,
           bloomTextureA.width == width,
           bloomTextureA.height == height,
           bloomTextureB.width == width,
           bloomTextureB.height == height {
            return (bloomTextureA, bloomTextureB)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        bloomTextureA = device.makeTexture(descriptor: descriptor)
        bloomTextureB = device.makeTexture(descriptor: descriptor)

        guard let bloomTextureA, let bloomTextureB else {
            return nil
        }

        return (bloomTextureA, bloomTextureB)
    }

    private func renderBloom(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        bloomTextureA: MTLTexture,
        bloomTextureB: MTLTexture,
        extractPipelineState: MTLRenderPipelineState,
        blurPipelineState: MTLRenderPipelineState
    ) {
        var extractUniforms = BloomUniforms(
            texelSize: SIMD2<Float>(
                1 / Float(sourceTexture.width),
                1 / Float(sourceTexture.height)
            ),
            direction: SIMD2<Float>(0, 0),
            threshold: 0.035,
            intensity: 1.0
        )

        renderFullscreenPass(
            commandBuffer: commandBuffer,
            pipelineState: extractPipelineState,
            outputTexture: bloomTextureA,
            inputTexture: sourceTexture,
            uniforms: &extractUniforms
        )

        var horizontalBlurUniforms = BloomUniforms(
            texelSize: SIMD2<Float>(
                1 / Float(bloomTextureA.width),
                1 / Float(bloomTextureA.height)
            ),
            direction: SIMD2<Float>(1, 0),
            threshold: 0,
            intensity: 1.0
        )

        renderFullscreenPass(
            commandBuffer: commandBuffer,
            pipelineState: blurPipelineState,
            outputTexture: bloomTextureB,
            inputTexture: bloomTextureA,
            uniforms: &horizontalBlurUniforms
        )

        var verticalBlurUniforms = BloomUniforms(
            texelSize: SIMD2<Float>(
                1 / Float(bloomTextureB.width),
                1 / Float(bloomTextureB.height)
            ),
            direction: SIMD2<Float>(0, 1),
            threshold: 0,
            intensity: 1.35
        )

        renderFullscreenPass(
            commandBuffer: commandBuffer,
            pipelineState: blurPipelineState,
            outputTexture: bloomTextureA,
            inputTexture: bloomTextureB,
            uniforms: &verticalBlurUniforms
        )
    }

    private func renderFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        pipelineState: MTLRenderPipelineState,
        outputTexture: MTLTexture,
        inputTexture: MTLTexture,
        uniforms: inout BloomUniforms
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = outputTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(inputTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BloomUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }
}
