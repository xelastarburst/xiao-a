import SwiftUI

/// Helferlein, drawn from the same 120×120 artwork as the mockups and app icon.
struct Mascot: View {
    enum Mood { case happy, calm, talking }

    var mood: Mood = .happy
    var size: CGFloat = 88
    var bobbing: Bool = true

    @State private var up = false

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 120
            ctx.scaleBy(x: s, y: s)

            var stem = Path()
            stem.move(to: CGPoint(x: 60, y: 26))
            stem.addLine(to: CGPoint(x: 60, y: 14))
            ctx.stroke(stem, with: .color(Palette.teal), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            var left = Path()
            left.move(to: CGPoint(x: 60, y: 16))
            left.addCurve(to: CGPoint(x: 39, y: 10), control1: CGPoint(x: 56, y: 7), control2: CGPoint(x: 45, y: 5))
            left.addCurve(to: CGPoint(x: 60, y: 16), control1: CGPoint(x: 44, y: 17), control2: CGPoint(x: 53, y: 19))
            ctx.fill(left, with: .color(Palette.leaf))

            var right = Path()
            right.move(to: CGPoint(x: 60, y: 16))
            right.addCurve(to: CGPoint(x: 81, y: 10), control1: CGPoint(x: 64, y: 7), control2: CGPoint(x: 75, y: 5))
            right.addCurve(to: CGPoint(x: 60, y: 16), control1: CGPoint(x: 76, y: 17), control2: CGPoint(x: 67, y: 19))
            ctx.fill(right, with: .color(Palette.leaf))

            ctx.fill(Path(ellipseIn: CGRect(x: 14, y: 27, width: 92, height: 86)), with: .color(Palette.mascot))
            ctx.fill(Path(ellipseIn: CGRect(x: 27, y: 50, width: 66, height: 54)), with: .color(Palette.face))

            switch mood {
            case .calm:
                var eyes = Path()
                eyes.move(to: CGPoint(x: 42, y: 72))
                eyes.addQuadCurve(to: CGPoint(x: 52, y: 72), control: CGPoint(x: 47, y: 66))
                eyes.move(to: CGPoint(x: 68, y: 72))
                eyes.addQuadCurve(to: CGPoint(x: 78, y: 72), control: CGPoint(x: 73, y: 66))
                ctx.stroke(eyes, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            case .happy, .talking:
                ctx.fill(Path(ellipseIn: CGRect(x: 42, y: 65.5, width: 10, height: 13)), with: .color(Palette.ink))
                ctx.fill(Path(ellipseIn: CGRect(x: 68, y: 65.5, width: 10, height: 13)), with: .color(Palette.ink))
                ctx.fill(Path(ellipseIn: CGRect(x: 47, y: 68, width: 3.6, height: 3.6)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: 73, y: 68, width: 3.6, height: 3.6)), with: .color(.white))
            }

            ctx.fill(Path(ellipseIn: CGRect(x: 30.5, y: 80, width: 13, height: 8)), with: .color(Palette.blush.opacity(0.5)))
            ctx.fill(Path(ellipseIn: CGRect(x: 76.5, y: 80, width: 13, height: 8)), with: .color(Palette.blush.opacity(0.5)))

            if mood == .talking {
                ctx.fill(Path(ellipseIn: CGRect(x: 54, y: 83, width: 12, height: 10)), with: .color(Palette.ink))
            } else {
                var smile = Path()
                smile.move(to: CGPoint(x: 52, y: 86))
                smile.addQuadCurve(to: CGPoint(x: 68, y: 86), control: CGPoint(x: 60, y: 94))
                ctx.stroke(smile, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .offset(y: bobbing && up ? -3 : 0)
        .onAppear {
            guard bobbing else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { up = true }
        }
        .accessibilityLabel("Helferlein")
    }
}
