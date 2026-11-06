import SwiftUI

enum MascotMood: String, CaseIterable, Identifiable, Equatable {
    case idle
    case dancing
    case confused
    case spinning
    case shock
    case sleeping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "Idle"
        case .dancing: "Dance"
        case .confused: "Confused"
        case .spinning: "Spin"
        case .shock: "Shock"
        case .sleeping: "Sleep"
        }
    }

    /// Lively moods need smooth motion; calm ones look fine at a lower frame rate.
    var frameInterval: TimeInterval {
        switch self {
        case .idle, .sleeping: 1.0 / 15
        case .dancing, .confused, .spinning, .shock: 1.0 / 30
        }
    }
}

/// The mascot: a soft white pouch with cards peeking out, drawn in code.
/// `color` tints the cards; the pouch itself stays white.
struct MascotView: View {
    let mood: MascotMood
    let color: Color
    /// Audio loudness 0...1; makes the dance bigger.
    let energy: Double
    let size: CGFloat
    /// Freezes the animation at one moment; used by the debug snapshot tool.
    var fixedTime: TimeInterval? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: mood.frameInterval, paused: fixedTime != nil)) { context in
            MascotCanvas(
                time: fixedTime ?? context.date.timeIntervalSinceReferenceDate,
                mood: mood,
                color: color,
                energy: energy
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Mascot, \(mood.title)")
    }
}

private struct MascotCanvas: View {
    let time: TimeInterval
    let mood: MascotMood
    let color: Color
    let energy: Double

    private static let ink = Color(red: 0.07, green: 0.07, blue: 0.09)
    private static let pouchTop = Color(white: 1.0)
    private static let pouchBottom = Color(white: 0.84)
    private static let edge = Color.black.opacity(0.14)

    var body: some View {
        Canvas { context, size in
            draw(in: &context, s: min(size.width, size.height))
        }
    }

    private func draw(in context: inout GraphicsContext, s: CGFloat) {
        let pose = Pose(mood: mood, time: time, energy: energy)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        // Pivot near the bottom tip, so squash, tilt and spin look grounded.
        let pivot = p(0.5, 0.92)
        var figure = context
        figure.translateBy(x: pivot.x + pose.jitterX * s, y: pivot.y - pose.bounce * s)
        figure.rotate(by: .degrees(pose.tilt))
        figure.scaleBy(x: pose.scaleX, y: pose.scaleY)
        figure.translateBy(x: -pivot.x, y: -pivot.y)

        let detailed = s >= 34

        // Cards peeking out of the pouch, back to front.
        let cardTints: [Double] = [0.55, 0.3, 0]
        for (index, lighten) in cardTints.enumerated() {
            let lift = pose.cardLift[index]
            let rect = CGRect(
                x: (0.22 + CGFloat(index) * 0.015) * s,
                y: (0.12 + CGFloat(index) * 0.045 - lift) * s,
                width: (0.56 - CGFloat(index) * 0.03) * s,
                height: 0.24 * s
            )
            var card = figure
            card.translateBy(x: rect.midX, y: rect.maxY)
            card.rotate(by: .degrees(pose.cardTilt[index]))
            card.translateBy(x: -rect.midX, y: -rect.maxY)
            let path = Path(roundedRect: rect, cornerRadius: 0.06 * s)
            card.fill(path, with: .color(color))
            card.fill(path, with: .color(.white.opacity(lighten)))
            card.stroke(path, with: .color(Self.edge), lineWidth: 0.008 * s)
        }

        // Back panel of the pouch.
        let back = Path(roundedRect: CGRect(x: 0.1 * s, y: 0.27 * s, width: 0.8 * s, height: 0.17 * s), cornerRadius: 0.085 * s)
        figure.fill(back, with: .linearGradient(Gradient(colors: [Color(white: 0.93), Color(white: 0.8)]), startPoint: p(0.5, 0.27), endPoint: p(0.5, 0.44)))
        figure.stroke(back, with: .color(Self.edge), lineWidth: 0.008 * s)

        // Front flap: rounded, upside-down triangle.
        let front = Self.roundedTriangle(p(0.08, 0.33), p(0.92, 0.33), p(0.5, 0.96), radius: 0.09 * s)
        figure.fill(front, with: .linearGradient(Gradient(colors: [Self.pouchTop, Self.pouchBottom]), startPoint: p(0.5, 0.33), endPoint: p(0.5, 0.96)))
        figure.stroke(front, with: .color(Self.edge), lineWidth: 0.01 * s)

        // While spinning we only see the face half of the turn.
        guard pose.facingFront else { return }

        if detailed {
            let stitch = Self.roundedTriangle(p(0.155, 0.375), p(0.845, 0.375), p(0.5, 0.895), radius: 0.06 * s)
            figure.stroke(
                stitch,
                with: .color(Color(white: 0.55).opacity(0.7)),
                style: StrokeStyle(lineWidth: 0.009 * s, lineCap: .round, dash: [0.022 * s, 0.018 * s])
            )
        }

        // Clasp strap with a snap button on the right side.
        let strap = Path(roundedRect: CGRect(x: 0.66 * s, y: 0.5 * s, width: 0.27 * s, height: 0.15 * s), cornerRadius: 0.075 * s)
        figure.fill(strap, with: .linearGradient(Gradient(colors: [Self.pouchTop, Color(white: 0.88)]), startPoint: p(0.8, 0.5), endPoint: p(0.8, 0.65)))
        figure.stroke(strap, with: .color(Self.edge), lineWidth: 0.009 * s)
        if detailed {
            let button = CGRect(x: 0.735 * s, y: 0.53 * s, width: 0.09 * s, height: 0.09 * s)
            figure.fill(Path(ellipseIn: button), with: .color(Color(white: 0.9)))
            figure.stroke(Path(ellipseIn: button), with: .color(Self.edge), lineWidth: 0.008 * s)
            figure.fill(Path(ellipseIn: button.insetBy(dx: button.width * 0.28, dy: button.height * 0.28).offsetBy(dx: -button.width * 0.1, dy: -button.height * 0.1)), with: .color(.white))
        }

        drawEyes(in: &figure, s: s, pose: pose)
        drawExtras(in: &context, s: s, pose: pose)
    }

    // MARK: - Face

    private func drawEyes(in figure: inout GraphicsContext, s: CGFloat, pose: Pose) {
        let centerX: CGFloat = 0.44 + pose.lookX
        let eyeY: CGFloat = 0.55
        let spacing: CGFloat = 0.09

        for side in [-1.0, 1.0] as [CGFloat] {
            let x = (centerX + side * spacing) * s
            let y = eyeY * s
            switch mood {
            case .dancing:
                // Happy "^" eyes that bob with the beat.
                var arc = Path()
                let w = 0.052 * s
                let bob = pose.eyeBob * s
                arc.move(to: CGPoint(x: x - w, y: y + w * 0.5 + bob))
                arc.addQuadCurve(to: CGPoint(x: x + w, y: y + w * 0.5 + bob), control: CGPoint(x: x, y: y - w * 1.3 + bob))
                figure.stroke(arc, with: .color(Self.ink), style: StrokeStyle(lineWidth: 0.032 * s, lineCap: .round))
            case .sleeping:
                var line = Path()
                let w = 0.04 * s
                line.move(to: CGPoint(x: x - w, y: y))
                line.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x, y: y + w * 0.9))
                figure.stroke(line, with: .color(Self.ink), style: StrokeStyle(lineWidth: 0.026 * s, lineCap: .round))
            case .shock:
                // Wide round eyes.
                let d = 0.14 * s
                let eye = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                figure.fill(Path(ellipseIn: eye), with: .color(Self.ink))
                figure.fill(Path(ellipseIn: CGRect(x: eye.minX + d * 0.18, y: eye.minY + d * 0.14, width: d * 0.36, height: d * 0.36)), with: .color(.white))
            case .idle, .confused, .spinning:
                // Tall pill eyes like the reference; the confused right eye is smaller and higher.
                var width = 0.078 * s
                var height = 0.175 * s
                var offsetY: CGFloat = 0
                if mood == .confused && side > 0 {
                    width *= 0.8
                    height *= 0.62
                    offsetY = -0.03 * s
                }
                if pose.blink { height = 0.018 * s }
                let eye = CGRect(x: x - width / 2, y: y - height / 2 + offsetY, width: width, height: height)
                figure.fill(Path(roundedRect: eye, cornerRadius: width / 2), with: .color(Self.ink))
                if !pose.blink {
                    let glint = CGRect(x: eye.minX + width * 0.22, y: eye.minY + height * 0.1, width: width * 0.36, height: height * 0.28)
                    figure.fill(Path(roundedRect: glint, cornerRadius: width * 0.18), with: .color(.white.opacity(0.85)))
                }
            }
        }
    }

    /// Symbols around the mascot; skipped at small sizes where they would be noise.
    private func drawExtras(in context: inout GraphicsContext, s: CGFloat, pose: Pose) {
        guard s >= 40 else { return }
        func symbol(_ text: String, size: CGFloat, at point: CGPoint, opacity: Double) {
            var layer = context
            layer.opacity = opacity
            layer.draw(Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(.white), at: point)
        }

        switch mood {
        case .dancing:
            for index in 0..<2 {
                let progress = (time * 0.6 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                let side: CGFloat = index == 0 ? 1 : -1
                symbol("♪", size: s * 0.2, at: CGPoint(x: s * (0.5 + side * 0.44) + sin(progress * 6) * s * 0.04, y: s * (0.32 - progress * 0.28)), opacity: 1 - progress)
            }
        case .confused:
            let wobble = sin(time * 3) * 0.02
            symbol("?", size: s * 0.24, at: CGPoint(x: s * (0.84 + wobble), y: s * 0.14), opacity: 0.95)
        case .shock:
            let pulse = 0.85 + 0.15 * sin(time * 14)
            symbol("!", size: s * 0.26 * pulse, at: CGPoint(x: s * 0.86, y: s * 0.13), opacity: 1)
        case .sleeping:
            let progress = (time * 0.4).truncatingRemainder(dividingBy: 1)
            symbol("z", size: s * (0.13 + 0.08 * progress), at: CGPoint(x: s * (0.82 + progress * 0.08), y: s * (0.3 - progress * 0.22)), opacity: 1 - progress)
        case .spinning:
            // Two swoosh arcs that suggest rotation.
            var swoosh = context
            swoosh.opacity = 0.55
            for side in [-1.0, 1.0] as [CGFloat] {
                var arc = Path()
                let start = Angle.degrees(side < 0 ? 140 : -40)
                arc.addArc(center: CGPoint(x: s * 0.5, y: s * 0.6), radius: s * 0.47, startAngle: start, endAngle: start + .degrees(60), clockwise: false)
                swoosh.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
            }
        case .idle:
            break
        }
    }

    // MARK: - Geometry

    /// Triangle with each corner rounded by `radius`.
    static func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let start = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        path.move(to: start)
        path.addArc(tangent1End: b, tangent2End: c, radius: radius)
        path.addArc(tangent1End: c, tangent2End: a, radius: radius * 1.3)
        path.addArc(tangent1End: a, tangent2End: b, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// Body motion for each mood at a given moment. Distances are fractions of the mascot size.
private struct Pose {
    var bounce: CGFloat = 0
    var jitterX: CGFloat = 0
    var tilt: Double = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var lookX: CGFloat = 0
    var eyeBob: CGFloat = 0
    var blink = false
    var facingFront = true
    var cardLift: [CGFloat] = [0, 0, 0]
    var cardTilt: [Double] = [-4, 3, 0]

    init(mood: MascotMood, time: TimeInterval, energy: Double) {
        switch mood {
        case .idle:
            scaleY = 1 + sin(time * 2) * 0.015
            scaleX = 1 - sin(time * 2) * 0.008
            blink = time.truncatingRemainder(dividingBy: 4.2) < 0.13
            cardLift = [0.01 * sin(time * 2), 0.01 * sin(time * 2 + 1), 0]

        case .dancing:
            let beat = time * 2.0 // about 120 BPM
            let strength = 0.6 + 0.6 * min(max(energy, 0), 1)
            bounce = abs(sin(beat * .pi)) * 0.08 * strength
            tilt = sin(beat * .pi) * 11 * strength
            scaleY = 1 + cos(beat * 2 * .pi) * 0.05 * strength
            scaleX = 1 - cos(beat * 2 * .pi) * 0.04 * strength
            eyeBob = sin(beat * 2 * .pi) * 0.008
            // Cards flutter one after another.
            cardLift = (0..<3).map { 0.03 * strength * max(0, sin(beat * 2 * .pi - Double($0) * 0.9)) }
            cardTilt = [-6 + sin(beat * .pi) * 6, 4 - sin(beat * .pi) * 5, sin(beat * .pi) * 3]

        case .confused:
            let sway = sin(time * 1.6)
            tilt = sway * 13
            lookX = sway * 0.02
            bounce = abs(sin(time * 1.6)) * 0.01
            cardTilt = [-8, 6, -2]
            blink = time.truncatingRemainder(dividingBy: 3.1) < 0.12

        case .spinning:
            // One full turntable turn every 1.2 s, with a little hop.
            let angle = time * 2 * .pi / 1.2
            scaleX = CGFloat(cos(angle))
            facingFront = cos(angle) > 0
            bounce = abs(sin(angle)) * 0.05
            cardLift = [0.02, 0.015, 0.01].map { $0 * CGFloat(abs(sin(angle))) }

        case .shock:
            // 1.4 s loop: crouch, jump, land, then tremble.
            let phase = time.truncatingRemainder(dividingBy: 1.4) / 1.4
            switch phase {
            case ..<0.12:
                let t = phase / 0.12
                scaleY = 1 - 0.14 * t
                scaleX = 1 + 0.08 * t
            case ..<0.42:
                let t = (phase - 0.12) / 0.3
                bounce = sin(t * .pi) * 0.13
                scaleY = 1.1 - 0.1 * t
                scaleX = 0.94 + 0.06 * t
                cardLift = [0.09, 0.07, 0.05].map { $0 * CGFloat(sin(t * .pi)) }
            case ..<0.52:
                let t = (phase - 0.42) / 0.1
                scaleY = 1 - 0.08 * sin(t * .pi)
                scaleX = 1 + 0.05 * sin(t * .pi)
            default:
                jitterX = sin(time * 70) * 0.012
                cardLift = [0.015, 0.01, 0.005]
            }
            cardTilt = [-10, 8, -3]

        case .sleeping:
            scaleY = 1 + sin(time * 1.3) * 0.03
            cardLift = [-0.02, -0.015, -0.01]
            cardTilt = [-2, 2, 0]
        }
    }
}
