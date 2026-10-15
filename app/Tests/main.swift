import Foundation
import CoreGraphics

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS \(message)")
}

let display = CGRect(x: -1440, y: 38, width: 1440, height: 862)
let pet = CGSize(width: 180, height: 210)
let recovered = PetGeometry.constrainedOrigin(CGPoint(x: -1600, y: 950), size: pet, bounds: display)
check(recovered == CGPoint(x: -1440, y: 690), "Recover off-screen pet on a display with negative coordinates")
let untouched = PetGeometry.constrainedOrigin(CGPoint(x: -800, y: 100), size: pet, bounds: display)
check(untouched == CGPoint(x: -800, y: 100), "Keep a valid dragged position")
let oversized = PetGeometry.constrainedOrigin(CGPoint(x: 100, y: -100), size: CGSize(width: 2000, height: 1200), bounds: display)
check(oversized == display.origin, "Oversized windows have a stable origin")
let right = PetGeometry.walk(x: -181, width: 180, bounds: display, direction: 1, speed: 30, elapsed: 0.1)
check(right.x == -180 && right.direction == -1, "Reverse at right edge without clipping")
let left = PetGeometry.walk(x: -1439, width: 180, bounds: display, direction: -1, speed: 30, elapsed: 0.1)
check(left.x == -1440 && left.direction == 1, "Reverse at left edge without clipping")
let resumed = PetGeometry.walk(x: -800, width: 180, bounds: display, direction: 1, speed: 30, elapsed: 60)
check(resumed.x == -797, "A wake from sleep cannot teleport the pet")
var x: CGFloat = -800
var heading: CGFloat = 1
for _ in 0..<20000 {
    let step = PetGeometry.walk(x: x, width: 180, bounds: display, direction: heading, speed: 48, elapsed: 1.0 / 30.0)
    x = step.x; heading = step.direction
    checkNoOutput(x >= display.minX && x <= display.maxX - 180)
}
func checkNoOutput(_ value: Bool) { if !value { fatalError("Pet escaped display") } }
print("PASS Long walk remains on-screen through repeated direction reversals")
check(PetGeometry.jumpHeight(progress: 0, amplitude: 64) == 0, "Jump starts on the baseline")
check(abs(PetGeometry.jumpHeight(progress: 0.5, amplitude: 64) - 64) < 0.001, "Jump reaches the intended peak")
check(PetGeometry.jumpHeight(progress: 1.2, amplitude: 64) == 0, "Jump returns to the exact baseline")
