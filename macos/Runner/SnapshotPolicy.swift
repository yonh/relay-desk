import CoreGraphics
import Foundation

/// Pure decision layer for the read-only viewport snapshot.
///
/// Everything in this file is free of Flutter/AppKit/WebKit dependencies so it
/// can be compiled and exercised standalone by the fixture under
/// `test/fixtures/snapshot/` — the same production code `takeSnapshot` calls.
enum SnapshotPolicy {
    /// Per-side pixel budget: bounds × backingScaleFactor, per dimension.
    static let maxPixelDimension: Double = 16384
    /// Total pixel budget for the captured bitmap.
    static let maxTotalPixels: Double = 64 * 1024 * 1024
    /// Encoded PNG byte budget.
    static let maxPngBytes = 16 * 1024 * 1024
    /// One-shot completion deadline for a single snapshot request.
    static let deadline: TimeInterval = 8

    enum BoundsVerdict: Equatable {
        /// Viewport is measurable and inside the pixel budget.
        case ok(pixelsWide: Double, pixelsHigh: Double)
        /// Zero, negative, non-finite, or otherwise unmeasurable bounds.
        case notMeasurable
        /// Measurable but outside the pixel budget (per-side or total).
        case tooLarge(pixelsWide: Double, pixelsHigh: Double)
    }

    /// Validates the viewport bounds BEFORE any native pixel allocation.
    /// `scale` is the window's backingScaleFactor the bitmap will be sampled
    /// at; it must be finite and positive for the check to be meaningful —
    /// a bogus scale is treated as an unmeasurable viewport.
    static func validate(bounds: CGSize, scale: CGFloat) -> BoundsVerdict {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            return .notMeasurable
        }
        guard scale.isFinite, scale > 0 else {
            return .notMeasurable
        }
        let pixelsWide = bounds.width * scale
        let pixelsHigh = bounds.height * scale
        // Multiplying two finite Doubles can overflow to +inf; that still
        // compares correctly against the budgets below and never traps.
        guard pixelsWide <= maxPixelDimension,
              pixelsHigh <= maxPixelDimension,
              pixelsWide * pixelsHigh <= maxTotalPixels else {
            return .tooLarge(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh)
        }
        return .ok(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh)
    }

    static func exceedsPngLimit(_ byteCount: Int) -> Bool {
        byteCount > maxPngBytes
    }

    /// Formats a pixel dimension for diagnostics without trapping. `Int()`
    /// would crash on finite-but-huge Doubles (e.g. 1e300), so this renders
    /// the floating-point value directly.
    static func describePixels(_ pixelsWide: Double, _ pixelsHigh: Double) -> String {
        String(format: "%.0fx%.0f", pixelsWide, pixelsHigh)
    }
}

/// The factors a snapshot request is bound to at capture start. All of them
/// are re-verified when the WebKit callback returns: the registry's current
/// instance for the viewId, its remapped identity, both navigation
/// generations (provisional starts AND commits — a same-URL reload bumps the
/// commit generation without changing the URL), and the window number.
struct SnapshotTargetBinding: Equatable {
    let viewId: Int64
    let identityId: String
    let instanceId: ObjectIdentifier
    let provisionalGeneration: Int
    let commitGeneration: Int
    let windowNumber: Int

    /// True only if every bound factor is unchanged. `liveInstance` must be
    /// the registry's *current* instance for `viewId` — a destroyed or
    /// replaced view is a different ObjectIdentifier.
    func isStillBound(
        liveInstance: AnyObject?,
        liveIdentityId: String?,
        liveProvisionalGeneration: Int,
        liveCommitGeneration: Int,
        liveWindowNumber: Int?
    ) -> Bool {
        guard let liveInstance,
              ObjectIdentifier(liveInstance) == instanceId else {
            return false
        }
        guard let liveWindowNumber, liveWindowNumber == windowNumber else {
            return false
        }
        return liveIdentityId == identityId
            && liveProvisionalGeneration == provisionalGeneration
            && liveCommitGeneration == commitGeneration
    }
}

/// One-shot completion for a single snapshot request. All plugin channel
/// calls run on the main thread, so a plain flag is sufficient: whoever
/// claims the gate first (deadline or WebKit callback) delivers the result;
/// the loser returns immediately — no double result, and a late callback
/// never reaches transcoding or a success payload.
final class SnapshotCompletionGate {
    private var claimed = false

    /// Claims the single completion slot. The first call returns true;
    /// every subsequent call returns false.
    func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }

    var isClaimed: Bool { claimed }
}
