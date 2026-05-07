import SwiftUI

struct FireworksSettings: Equatable {
    var explosionRadius: Float = 0.28
    var particleSize: Float = 0.23
    var particleBlur: Float = 0.36
    var glowIntensity: Float = 62.5
    var glowRadius: Float = 104.36
    var fadeSpeed: Float = 1.68
    var flightSpeed: Float = 1.81
    var gravity: Float = 0.14
    var trailBrightness: Float = 10.0
    var trailLength: Float = 1.4
    var maxVisibleParticleInstances: Float = 44_000
}

enum EffectKind: String, CaseIterable, Identifiable {
    case fireworks
    case ripple

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fireworks:
            "Fireworks"
        case .ripple:
            "Ripple"
        }
    }
}

struct RippleSettings: Equatable {
    var strength: Float = 0.03
    var radius: Float = 0.46
    var speed: Float = 2.17
    var damping: Float = 1.08
    var refraction: Float = 0.78
    var waveCount: Float = 2
    var waveSoftness: Float = 1.0
    var fadeSpeed: Float = 1.0
    var waveSpacing: Float = 0.35
}

struct ContentView: View {
    @State private var settings = FireworksSettings()
    @State private var rippleSettings = RippleSettings()
    @State private var selectedEffect = EffectKind.fireworks
    @State private var isSettingsPresented = false
    @State private var framesPerSecond = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            switch selectedEffect {
            case .fireworks:
                FireworksMetalView(settings: settings, framesPerSecond: $framesPerSecond)
                    .ignoresSafeArea()
            case .ripple:
                RippleMetalView(settings: rippleSettings, framesPerSecond: $framesPerSecond)
                    .ignoresSafeArea()
            }

            RewardOverlay()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            HStack {
                Text("\(framesPerSecond) FPS")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.black.opacity(0.35), in: Capsule())

                Spacer()

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("Settings")
            }
            .padding(.top, 12)
            .padding(.horizontal, 14)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(
                selectedEffect: $selectedEffect,
                fireworksSettings: $settings,
                rippleSettings: $rippleSettings
            )
                .presentationDetents([.height(680)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black.opacity(0.88))
        }
    }
}

private struct RewardOverlay: View {
    var body: some View {
        ZStack {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("+1 500")
                    Text("₽")
                        .tracking(-1.2)
                }
                .font(.system(size: 69, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Text("Happy birthday!")
                    .font(.system(size: 20, weight: .regular))
                    .tracking(-0.63)
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    Image("AlexeyAvatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())

                    Text("Alexey K.")
                        .font(.system(size: 16, weight: .regular))
                        .tracking(-0.25)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.leading, 4)
                .padding(.trailing, 15)
                .frame(height: 40)
                .background(.white.opacity(0.2), in: Capsule())
                .padding(.top, 16)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 340, height: 230)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("+1 500 rubles. Happy birthday. Alexey K.")
    }
}

private struct SettingsSheet: View {
    @Binding var selectedEffect: EffectKind
    @Binding var fireworksSettings: FireworksSettings
    @Binding var rippleSettings: RippleSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.headline)
                    .foregroundStyle(.white)

                Picker("Effect", selection: $selectedEffect) {
                    ForEach(EffectKind.allCases) { effect in
                        Text(effect.title).tag(effect)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedEffect {
                case .fireworks:
                    fireworksControls
                case .ripple:
                    rippleControls
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
    }

    private var fireworksControls: some View {
        VStack(alignment: .leading, spacing: 22) {
            SliderRow(
                title: "Explosion radius",
                value: Binding(
                    get: { Double(fireworksSettings.explosionRadius) },
                    set: { fireworksSettings.explosionRadius = Float($0) }
                ),
                range: 0.1...1.8
            )

            SliderRow(
                title: "Particle size",
                value: Binding(
                    get: { Double(fireworksSettings.particleSize) },
                    set: { fireworksSettings.particleSize = Float($0) }
                ),
                range: 0.11...1
            )

            SliderRow(
                title: "Particle blur",
                value: Binding(
                    get: { Double(fireworksSettings.particleBlur) },
                    set: { fireworksSettings.particleBlur = Float($0) }
                ),
                range: 0...1
            )

            SliderRow(
                title: "Glow intensity",
                value: Binding(
                    get: { Double(fireworksSettings.glowIntensity) },
                    set: { fireworksSettings.glowIntensity = Float($0) }
                ),
                range: 0...62.5
            )

            SliderRow(
                title: "Glow radius",
                value: Binding(
                    get: { Double(fireworksSettings.glowRadius) },
                    set: { fireworksSettings.glowRadius = Float($0) }
                ),
                range: 20...220
            )

            SliderRow(
                title: "Fade speed",
                value: Binding(
                    get: { Double(fireworksSettings.fadeSpeed) },
                    set: { fireworksSettings.fadeSpeed = Float($0) }
                ),
                range: 0.4...4
            )

            SliderRow(
                title: "Flight speed",
                value: Binding(
                    get: { Double(fireworksSettings.flightSpeed) },
                    set: { fireworksSettings.flightSpeed = Float($0) }
                ),
                range: 0.35...2
            )

            SliderRow(
                title: "Gravity",
                value: Binding(
                    get: { Double(fireworksSettings.gravity) },
                    set: { fireworksSettings.gravity = Float($0) }
                ),
                range: 0.05...1.4
            )

            SliderRow(
                title: "Max particles on screen",
                value: Binding(
                    get: { Double(fireworksSettings.maxVisibleParticleInstances) },
                    set: { fireworksSettings.maxVisibleParticleInstances = Float(($0 / 500).rounded() * 500) }
                ),
                range: 6_000...60_000,
                fractionLength: 0
            )

            SliderRow(
                title: "Trail brightness",
                value: Binding(
                    get: { Double(fireworksSettings.trailBrightness) },
                    set: { fireworksSettings.trailBrightness = Float($0) }
                ),
                range: 1...10
            )

            SliderRow(
                title: "Trail length",
                value: Binding(
                    get: { Double(fireworksSettings.trailLength) },
                    set: { fireworksSettings.trailLength = Float($0) }
                ),
                range: 0.15...1.4
            )
        }
    }

    private var rippleControls: some View {
        VStack(alignment: .leading, spacing: 22) {
            SliderRow(
                title: "Ripple strength",
                value: Binding(
                    get: { Double(rippleSettings.strength) },
                    set: { rippleSettings.strength = Float($0) }
                ),
                range: 0.01...0.12
            )

            SliderRow(
                title: "Ripple radius",
                value: Binding(
                    get: { Double(rippleSettings.radius) },
                    set: { rippleSettings.radius = Float($0) }
                ),
                range: 0.18...0.9
            )

            SliderRow(
                title: "Ripple speed",
                value: Binding(
                    get: { Double(rippleSettings.speed) },
                    set: { rippleSettings.speed = Float($0) }
                ),
                range: 0.6...3
            )

            SliderRow(
                title: "Wave count",
                value: Binding(
                    get: { Double(rippleSettings.waveCount) },
                    set: { rippleSettings.waveCount = Float($0.rounded()) }
                ),
                range: 1...8,
                fractionLength: 0
            )

            SliderRow(
                title: "Wave softness",
                value: Binding(
                    get: { Double(rippleSettings.waveSoftness) },
                    set: { rippleSettings.waveSoftness = Float($0) }
                ),
                range: 0.05...1
            )

            SliderRow(
                title: "Wave spacing",
                value: Binding(
                    get: { Double(rippleSettings.waveSpacing) },
                    set: { rippleSettings.waveSpacing = Float($0) }
                ),
                range: 0.35...2
            )

            SliderRow(
                title: "Fade speed",
                value: Binding(
                    get: { Double(rippleSettings.fadeSpeed) },
                    set: { rippleSettings.fadeSpeed = Float($0) }
                ),
                range: 0.15...3
            )

            SliderRow(
                title: "Damping",
                value: Binding(
                    get: { Double(rippleSettings.damping) },
                    set: { rippleSettings.damping = Float($0) }
                ),
                range: 0.35...2.2
            )

            SliderRow(
                title: "Refraction",
                value: Binding(
                    get: { Double(rippleSettings.refraction) },
                    set: { rippleSettings.refraction = Float($0) }
                ),
                range: 0.2...1.6
            )
        }
    }

}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var fractionLength = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(fractionLength)))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.68))
            }
            .font(.subheadline)
            .foregroundStyle(.white)

            Slider(value: $value, in: range)
                .tint(.white)
        }
    }
}

#Preview {
    ContentView()
}
