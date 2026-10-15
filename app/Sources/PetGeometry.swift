import Foundation
import CoreGraphics

enum PetGeometry {
    static func constrainedOrigin(_ origin: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        let maxX = max(bounds.minX, bounds.maxX - size.width)
        let maxY = max(bounds.minY, bounds.maxY - size.height)
        return CGPoint(x: min(max(origin.x, bounds.minX), maxX),
                       y: min(max(origin.y, bounds.minY), maxY))
    }

    static func walk(x: CGFloat, width: CGFloat, bounds: CGRect,
                     direction: CGFloat, speed: CGFloat, elapsed: TimeInterval) -> (x: CGFloat, direction: CGFloat) {
        let next = x + direction * speed * CGFloat(max(0, min(elapsed, 0.1)))
        let right = max(bounds.minX, bounds.maxX - width)
        if next <= bounds.minX { return (bounds.minX, 1) }
        if next >= right { return (right, -1) }
        return (next, direction)
    }

    static func jumpHeight(progress: Double, amplitude: CGFloat) -> CGFloat {
        guard progress > 0, progress < 1 else { return 0 }
        return CGFloat(sin(progress * .pi)) * amplitude
    }
}
