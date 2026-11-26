import SwiftUI

public enum PaperSurface: String, CaseIterable, Sendable {
    case sage
    case cream
    case lavender
    case ivory
    case sand

    public var color: Color {
        switch self {
        case .sage:
            // #B2C6B7 — muted sage green card ("Momentum is building")
            return Color(red: 0.698, green: 0.776, blue: 0.718)
        case .cream:
            // #F4EBC4 — warm cream sticky-note / notepad card
            return Color(red: 0.957, green: 0.922, blue: 0.769)
        case .lavender:
            // #BEB3CB — soft muted lavender card (Insights chart / Focus)
            return Color(red: 0.745, green: 0.702, blue: 0.796)
        case .ivory:
            // #ECECE8 — crisp off-white paper card
            return Color(red: 0.925, green: 0.925, blue: 0.910)
        case .sand:
            // #E8D9C8 — warm sand accent card
            return Color(red: 0.910, green: 0.851, blue: 0.784)
        }
    }
}

public enum PaperInk {
    public static let primary = Color(red: 0.090, green: 0.098, blue: 0.110)
    public static let secondary = Color(red: 0.227, green: 0.247, blue: 0.275)
    public static let muted = Color(red: 0.345, green: 0.369, blue: 0.404)
    public static let track = Color.black.opacity(0.12)
    public static let plannedBar = Color.black.opacity(0.18)
    public static let hairline = Color.black.opacity(0.09)
    public static let innerHighlight = Color.white.opacity(0.28)
}

/// Deterministic fine matte paper grain overlay drawn via Canvas with zero image assets.
public struct PaperGrainOverlay: View {
    public var seed: UInt64
    public var intensity: Double

    public init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15, intensity: Double = 1.0) {
        self.seed = seed
        self.intensity = intensity
    }

    public var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            var state = seed
            let area = size.width * size.height
            let dotCount = min(1400, max(180, Int(area / 55)))

            for i in 0..<dotCount {
                state ^= state >> 12
                state ^= state << 25
                state ^= state >> 27
                let v1 = state &* 0x2545_F491_4F6C_DD1D
                state ^= state >> 12
                state ^= state << 25
                state ^= state >> 27
                let v2 = state &* 0x2545_F491_4F6C_DD1D

                let x = CGFloat(v1 % 10_000) / 10_000.0 * size.width
                let y = CGFloat(v2 % 10_000) / 10_000.0 * size.height
                let radius: CGFloat = (i % 5 == 0) ? 1.15 : 0.75
                let isLight = (i % 2 == 0)
                let color = isLight
                    ? Color.white.opacity(0.16 * intensity)
                    : Color.black.opacity(0.065 * intensity)

                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                    with: .color(color)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

public struct PaperCardModifier: ViewModifier {
    let surface: PaperSurface
    let cornerRadius: CGFloat
    let grainSeed: UInt64

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(PaperInk.primary)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(surface.color)
                    PaperGrainOverlay(seed: grainSeed)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(PaperInk.innerHighlight, lineWidth: 0.75)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public extension View {
    func paperCard(
        _ surface: PaperSurface,
        cornerRadius: CGFloat = 14,
        grainSeed: UInt64 = 0x9E37_79B9_7F4A_7C15
    ) -> some View {
        modifier(PaperCardModifier(surface: surface, cornerRadius: cornerRadius, grainSeed: grainSeed))
    }
}

public struct PaperProgressBar: View {
    public let progress: Double
    public var height: CGFloat

    public init(progress: Double, height: CGFloat = 5) {
        self.progress = min(max(progress, 0), 1)
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PaperInk.track)
                Capsule()
                    .fill(PaperInk.primary)
                    .frame(width: max(progress > 0 ? height : 0, geo.size.width * progress))
            }
        }
        .frame(height: height)
    }
}

public struct PaperSegmentedControl<Option: Hashable & Identifiable>: View {
    public let options: [Option]
    @Binding public var selection: Option
    public let label: (Option) -> String

    public init(
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : PaperInk.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.black.opacity(0.28))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.14), in: Capsule())
    }
}
