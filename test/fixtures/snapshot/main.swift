import CoreGraphics
import Foundation

// Executable fixture for the native snapshot decision layer. Compiles the
// production macos/Runner/SnapshotPolicy.swift directly (see run.sh), so
// every assertion below exercises the same code takeSnapshot calls — not a
// stub or a copied table of constants.

var failures = 0
func check(_ name: String, _ condition: Bool) {
    if condition {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name)")
    }
}

// MARK: - Pixel budget: normal / degenerate / single-side / total / boundary

let normal = SnapshotPolicy.validate(bounds: CGSize(width: 279.5, height: 140.5), scale: 2)
check("validate: 2x viewport inside budget -> ok", normal == .ok(pixelsWide: 559, pixelsHigh: 281))

check("validate: zero width -> notMeasurable",
      SnapshotPolicy.validate(bounds: CGSize(width: 0, height: 100), scale: 2) == .notMeasurable)
check("validate: negative height -> notMeasurable",
      SnapshotPolicy.validate(bounds: CGSize(width: 100, height: -1), scale: 2) == .notMeasurable)
check("validate: infinite width -> notMeasurable",
      SnapshotPolicy.validate(bounds: CGSize(width: CGFloat.infinity, height: 100), scale: 1) == .notMeasurable)
check("validate: nan height -> notMeasurable",
      SnapshotPolicy.validate(bounds: CGSize(width: 100, height: CGFloat.nan), scale: 1) == .notMeasurable)
check("validate: non-finite scale -> notMeasurable",
      SnapshotPolicy.validate(bounds: CGSize(width: 100, height: 100), scale: CGFloat.infinity) == .notMeasurable)
check("validate: zero scale -> notMeasurable",
      SnapshotPolicy.validate(bounds: CGSize(width: 100, height: 100), scale: 0) == .notMeasurable)

// Single side over budget at 2x: 9000 * 2 = 18000 > 16384 even though the
// other dimension and the total are small.
if case .tooLarge(let w, let h) = SnapshotPolicy.validate(bounds: CGSize(width: 9000, height: 200), scale: 2) {
    check("validate: single side over -> tooLarge reports pixels", w == 18000 && h == 400)
} else {
    check("validate: single side over -> tooLarge reports pixels", false)
}
// Same bounds at 1x is fine: the scale is part of the judgment.
check("validate: same bounds at 1x -> ok",
      SnapshotPolicy.validate(bounds: CGSize(width: 9000, height: 200), scale: 1) == .ok(pixelsWide: 9000, pixelsHigh: 200))

// Total-pixel overflow with both sides under the per-side cap:
// 6000*6000*4 = 144 MP > 64 MP.
if case .tooLarge = SnapshotPolicy.validate(bounds: CGSize(width: 6000, height: 6000), scale: 2) {
    check("validate: total pixels over -> tooLarge", true)
} else {
    check("validate: total pixels over -> tooLarge", false)
}
// Exact boundary is allowed: 8192 * 2 = 16384 == cap, total 268 MP? no —
// 8192*2 = 16384 per side, 16384*16384 = 268 MP > 64 MP, so this is
// tooLarge on the TOTAL cap. Use a boundary that passes both caps:
// 8192x1000 @2 -> 16384x2000 px = 32.8 MP -> ok.
check("validate: exact per-side boundary -> ok",
      SnapshotPolicy.validate(bounds: CGSize(width: 8192, height: 1000), scale: 2) == .ok(pixelsWide: 16384, pixelsHigh: 2000))
// One point past the per-side cap -> tooLarge.
if case .tooLarge = SnapshotPolicy.validate(bounds: CGSize(width: 8192.5, height: 1000), scale: 2) {
    check("validate: just past per-side cap -> tooLarge", true)
} else {
    check("validate: just past per-side cap -> tooLarge", false)
}
// Both sides at the per-side cap: over the total cap.
if case .tooLarge = SnapshotPolicy.validate(bounds: CGSize(width: 8192, height: 8192), scale: 2) {
    check("validate: both sides at cap -> tooLarge on total", true)
} else {
    check("validate: both sides at cap -> tooLarge on total", false)
}
// Finite but huge bounds must be tooLarge, never a crash.
if case .tooLarge(let w, _) = SnapshotPolicy.validate(bounds: CGSize(width: 1e300, height: 1e300), scale: 2) {
    check("validate: finite-but-huge bounds -> tooLarge (huge finite, no trap)", w == 2e300)
} else {
    check("validate: finite-but-huge bounds -> tooLarge (huge finite, no trap)", false)
}
// Bounds so large that bounds*scale overflows to +inf still fail the guard
// cleanly (inf > cap) instead of trapping or wrapping.
if case .tooLarge(let w, _) = SnapshotPolicy.validate(bounds: CGSize(width: 1e308, height: 100), scale: 2) {
    check("validate: scale overflow to +inf -> tooLarge", w == .infinity)
} else {
    check("validate: scale overflow to +inf -> tooLarge", false)
}

// MARK: - describePixels never traps (Int() would crash on 1e300)

check("describePixels: huge finite values render, no trap",
      SnapshotPolicy.describePixels(Double.infinity, 16384.5) == "infx16385" ||
      SnapshotPolicy.describePixels(Double.infinity, 16384.5).hasPrefix("inf"))
check("describePixels: normal values", SnapshotPolicy.describePixels(559, 281) == "559x281")

// MARK: - PNG byte budget

check("exceedsPngLimit: at limit -> false", !SnapshotPolicy.exceedsPngLimit(16 * 1024 * 1024))
check("exceedsPngLimit: one byte over -> true", SnapshotPolicy.exceedsPngLimit(16 * 1024 * 1024 + 1))

// MARK: - Binding invalidation: commit gen / instance / window / identity

final class DummyView: NSObject {}
let originalInstance = DummyView()
let binding = SnapshotTargetBinding(
    viewId: 7,
    identityId: "id-A",
    instanceId: ObjectIdentifier(originalInstance),
    provisionalGeneration: 4,
    commitGeneration: 9,
    windowNumber: 42
)

check("binding: unchanged -> still bound",
      binding.isStillBound(liveInstance: originalInstance, liveIdentityId: "id-A",
                           liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: 42))
// Same-URL reload / mid-capture commit: only the commit generation moves.
check("binding: commit generation bumped (same-URL commit) -> not bound",
      !binding.isStillBound(liveInstance: originalInstance, liveIdentityId: "id-A",
                            liveProvisionalGeneration: 4, liveCommitGeneration: 10, liveWindowNumber: 42))
check("binding: provisional generation bumped -> not bound",
      !binding.isStillBound(liveInstance: originalInstance, liveIdentityId: "id-A",
                            liveProvisionalGeneration: 5, liveCommitGeneration: 9, liveWindowNumber: 42))
check("binding: instance replaced -> not bound",
      !binding.isStillBound(liveInstance: DummyView(), liveIdentityId: "id-A",
                            liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: 42))
check("binding: registry empty (view destroyed) -> not bound",
      !binding.isStillBound(liveInstance: nil, liveIdentityId: "id-A",
                            liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: 42))
check("binding: window changed -> not bound",
      !binding.isStillBound(liveInstance: originalInstance, liveIdentityId: "id-A",
                            liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: 43))
check("binding: window lost (nil) -> not bound",
      !binding.isStillBound(liveInstance: originalInstance, liveIdentityId: "id-A",
                            liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: nil))
check("binding: identity remapped -> not bound",
      !binding.isStillBound(liveInstance: originalInstance, liveIdentityId: "id-B",
                            liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: 42))
check("binding: identity lookup empty -> not bound",
      !binding.isStillBound(liveInstance: originalInstance, liveIdentityId: nil,
                            liveProvisionalGeneration: 4, liveCommitGeneration: 9, liveWindowNumber: 42))

// MARK: - One-shot completion gate: deadline vs late callback

let gateA = SnapshotCompletionGate()
check("gate: first claim wins", gateA.claim())
check("gate: second claim dropped (late callback)", !gateA.claim())
check("gate: still claimed after drop", gateA.isClaimed)

// Deadline-first ordering, the exact plugin pattern: the deadline claims
// the gate, then the late WebKit callback fails claim() and returns before
// delivering — one result total.
let gateB = SnapshotCompletionGate()
var delivered: [String] = []
func deliverOnce(_ value: String) {
    if gateB.claim() { delivered.append(value) }
}
deliverOnce("timeout")                // deadline fires first
deliverOnce("late-callback-result")   // late callback is dropped
check("gate: deadline-first ordering delivers exactly once, late callback dropped",
      delivered == ["timeout"])

if failures > 0 {
    print("RESULT: \(failures) failure(s)")
    exit(1)
}
print("RESULT: all snapshot policy fixtures passed")
