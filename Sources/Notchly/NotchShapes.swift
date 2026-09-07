import SwiftUI

// MARK: - Side rail notch (concave entry scoops + convex shoulders)

/// Apple-style curved notch docked to the right screen edge, with true
/// concave entry scoops where it meets the edge and convex shoulders.
/// Mirrored when docked to the left edge.
struct SideNotchShape: Shape {
    var flareWidth: CGFloat = 24
    var flareHeight: CGFloat = 36
    var cornerRadius: CGFloat = 28
    var mirrored = false

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(flareWidth, AnimatablePair(flareHeight, cornerRadius)) }
        set {
            flareWidth = newValue.first
            flareHeight = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let base = RightRailPath(flareWidth: flareWidth, flareHeight: flareHeight, cornerRadius: cornerRadius)
            .path(in: rect)
        guard mirrored else { return base }
        return base.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }

    private struct RightRailPath: Shape {
        var flareWidth: CGFloat
        var flareHeight: CGFloat
        var cornerRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let w = rect.width
            let h = rect.height
            let fh = min(flareHeight, h * 0.35)
            let cr = min(cornerRadius, max(2, (h - 2 * fh) * 0.5))
            let fw = min(flareWidth, max(2, w * 0.45))
            let k: CGFloat = 0.5522847

            // Start at top-right on the screen boundary.
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            // Concave scoop down to the flare shoulder.
            path.addCurve(to: CGPoint(x: rect.maxX - fw, y: rect.minY + fh),
                          control1: CGPoint(x: rect.maxX, y: rect.minY + fh * k),
                          control2: CGPoint(x: rect.maxX - fw * (1 - k), y: rect.minY + fh))
            // Top bridge into the convex shoulder.
            path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.minY + fh))
            path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + fh + cr),
                          control1: CGPoint(x: rect.minX + cr * (1 - k), y: rect.minY + fh),
                          control2: CGPoint(x: rect.minX, y: rect.minY + fh + cr * (1 - k)))
            // Free (left) edge.
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - fh - cr))
            path.addCurve(to: CGPoint(x: rect.minX + cr, y: rect.maxY - fh),
                          control1: CGPoint(x: rect.minX, y: rect.maxY - fh - cr * (1 - k)),
                          control2: CGPoint(x: rect.minX + cr * (1 - k), y: rect.maxY - fh))
            path.addLine(to: CGPoint(x: rect.maxX - fw, y: rect.maxY - fh))
            // Concave scoop back to the screen boundary.
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control1: CGPoint(x: rect.maxX - fw * (1 - k), y: rect.maxY - fh),
                          control2: CGPoint(x: rect.maxX, y: rect.maxY - fh * k))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Top island notch (concave ear fillets + rounded bottom)

/// Apple-style top notch with concave ear fillets where it meets the screen edge.
struct TopIslandShape: Shape {
    var flareWidth: CGFloat = 16
    var flareHeight: CGFloat = 16
    var cornerRadius: CGFloat = 20

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(flareWidth, AnimatablePair(flareHeight, cornerRadius)) }
        set {
            flareWidth = newValue.first
            flareHeight = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let fw = min(flareWidth, w * 0.25)
        let fh = min(flareHeight, h * 0.4)
        let cr = min(cornerRadius, max(2, min((w - 2 * fw) * 0.5, h - fh)))
        let k: CGFloat = 0.5522847

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear fillet.
        path.addCurve(to: CGPoint(x: rect.minX + fw, y: rect.minY + fh),
                      control1: CGPoint(x: rect.minX + fw * (1 - k), y: rect.minY),
                      control2: CGPoint(x: rect.minX + fw, y: rect.minY + fh * k))
        // Left side + bottom-left corner.
        path.addLine(to: CGPoint(x: rect.minX + fw, y: rect.maxY - cr))
        path.addCurve(to: CGPoint(x: rect.minX + fw + cr, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + fw, y: rect.maxY - cr * (1 - k)),
                      control2: CGPoint(x: rect.minX + fw + cr * (1 - k), y: rect.maxY))
        // Bottom edge + bottom-right corner.
        path.addLine(to: CGPoint(x: rect.maxX - fw - cr, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - fw, y: rect.maxY - cr),
                      control1: CGPoint(x: rect.maxX - fw - cr * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.maxX - fw, y: rect.maxY - cr * (1 - k)))
        // Right side + right ear fillet.
        path.addLine(to: CGPoint(x: rect.maxX - fw, y: rect.minY + fh))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: rect.maxX - fw, y: rect.minY + fh * k),
                      control2: CGPoint(x: rect.maxX - fw * (1 - k), y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Popover callout with beak

/// Detail card with an animatable beak pointing at the hovered rail item.
struct PopoverCalloutShape: Shape {
    var pointerY: CGFloat
    var pointerOnLeft = false
    var cornerRadius: CGFloat = 16
    var pointerWidth: CGFloat = 10
    var pointerHeight: CGFloat = 18

    var animatableData: CGFloat {
        get { pointerY }
        set { pointerY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let pw = pointerWidth
        let ph = pointerHeight / 2
        let cardRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width - pw, height: rect.height)
        let clampedY = min(max(pointerY, cardRect.minY + r + ph), cardRect.maxY - r - ph)

        path.move(to: CGPoint(x: cardRect.minX + r, y: cardRect.minY))
        path.addLine(to: CGPoint(x: cardRect.maxX - r, y: cardRect.minY))
        path.addArc(center: CGPoint(x: cardRect.maxX - r, y: cardRect.minY + r),
                    radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: cardRect.maxX, y: clampedY - ph))
        path.addLine(to: CGPoint(x: cardRect.maxX + pw, y: clampedY))
        path.addLine(to: CGPoint(x: cardRect.maxX, y: clampedY + ph))
        path.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.maxY - r))
        path.addArc(center: CGPoint(x: cardRect.maxX - r, y: cardRect.maxY - r),
                    radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: cardRect.minX + r, y: cardRect.maxY))
        path.addArc(center: CGPoint(x: cardRect.minX + r, y: cardRect.maxY - r),
                    radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: cardRect.minX, y: cardRect.minY + r))
        path.addArc(center: CGPoint(x: cardRect.minX + r, y: cardRect.minY + r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        guard pointerOnLeft else { return path }
        return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }
}

/// Detail card below the top island with a beak pointing up at the hovered item.
struct VerticalCalloutShape: Shape {
    var pointerX: CGFloat
    var cornerRadius: CGFloat = 16
    var pointerWidth: CGFloat = 18
    var pointerHeight: CGFloat = 10

    var animatableData: CGFloat {
        get { pointerX }
        set { pointerX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cardRect = CGRect(x: rect.minX, y: rect.minY + pointerHeight,
                              width: rect.width, height: rect.height - pointerHeight)
        let clampedX = min(max(pointerX, cardRect.minX + cornerRadius + pointerWidth / 2),
                           cardRect.maxX - cornerRadius - pointerWidth / 2)
        var path = Path(roundedRect: cardRect, cornerRadius: cornerRadius)
        var pointer = Path()
        pointer.move(to: CGPoint(x: clampedX - pointerWidth / 2, y: cardRect.minY))
        pointer.addLine(to: CGPoint(x: clampedX, y: rect.minY))
        pointer.addLine(to: CGPoint(x: clampedX + pointerWidth / 2, y: cardRect.minY))
        pointer.closeSubpath()
        path.addPath(pointer)
        return path
    }
}
