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

struct ContentView: View {
    @State private var settings = FireworksSettings()
    @State private var isSettingsPresented = false
    @State private var framesPerSecond = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            FireworksMetalView(settings: settings, framesPerSecond: $framesPerSecond)
                .ignoresSafeArea()

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
            SettingsSheet(settings: $settings)
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
    @Binding var settings: FireworksSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.headline)
                    .foregroundStyle(.white)

                SliderRow(
                    title: "Explosion radius",
                    value: Binding(
                        get: { Double(settings.explosionRadius) },
                        set: { settings.explosionRadius = Float($0) }
                    ),
                    range: 0.1...1.8
                )

                SliderRow(
                    title: "Particle size",
                    value: Binding(
                        get: { Double(settings.particleSize) },
                        set: { settings.particleSize = Float($0) }
                    ),
                    range: 0.11...1
                )

                SliderRow(
                    title: "Particle blur",
                    value: Binding(
                        get: { Double(settings.particleBlur) },
                        set: { settings.particleBlur = Float($0) }
                    ),
                    range: 0...1
                )

                SliderRow(
                    title: "Glow intensity",
                    value: Binding(
                        get: { Double(settings.glowIntensity) },
                        set: { settings.glowIntensity = Float($0) }
                    ),
                    range: 0...62.5
                )

                SliderRow(
                    title: "Glow radius",
                    value: Binding(
                        get: { Double(settings.glowRadius) },
                        set: { settings.glowRadius = Float($0) }
                    ),
                    range: 20...220
                )

                SliderRow(
                    title: "Fade speed",
                    value: Binding(
                        get: { Double(settings.fadeSpeed) },
                        set: { settings.fadeSpeed = Float($0) }
                    ),
                    range: 0.4...4
                )

                SliderRow(
                    title: "Flight speed",
                    value: Binding(
                        get: { Double(settings.flightSpeed) },
                        set: { settings.flightSpeed = Float($0) }
                    ),
                    range: 0.35...2
                )

                SliderRow(
                    title: "Gravity",
                    value: Binding(
                        get: { Double(settings.gravity) },
                        set: { settings.gravity = Float($0) }
                    ),
                    range: 0.05...1.4
                )

                SliderRow(
                    title: "Max particles on screen",
                    value: Binding(
                        get: { Double(settings.maxVisibleParticleInstances) },
                        set: { settings.maxVisibleParticleInstances = Float(($0 / 500).rounded() * 500) }
                    ),
                    range: 6_000...60_000,
                    fractionLength: 0
                )

                SliderRow(
                    title: "Trail brightness",
                    value: Binding(
                        get: { Double(settings.trailBrightness) },
                        set: { settings.trailBrightness = Float($0) }
                    ),
                    range: 1...10
                )

                SliderRow(
                    title: "Trail length",
                    value: Binding(
                        get: { Double(settings.trailLength) },
                        set: { settings.trailLength = Float($0) }
                    ),
                    range: 0.15...1.4
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 28)
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
