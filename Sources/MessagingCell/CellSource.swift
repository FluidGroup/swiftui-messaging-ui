import ContextOverlay
import UIKit

/// The message-cell name for a general context-overlay rendering reference.
///
/// Keep this object in the cell's SwiftUI state and pass it to ``MessageCell``.
/// The cell owns the UIKit rendering view; this reference does not prolong its
/// lifetime. Other overlay sources can use `ContextOverlaySource` directly.
public typealias CellSource = ContextOverlaySource

/// The caller-owned phase of a cell's handoff to a reply presentation.
public enum CellReplyPhase: Equatable, Sendable {
  /// The cell accepts a new right swipe.
  case idle
  /// A reply was accepted; keep the release position until its source is hidden.
  case preparing
  /// The overlay has hidden the source; its translation may return to zero.
  case presented
}

/// The rubber-banded model target and physical velocity at release of a right drag.
public struct CellReplyRelease: Equatable, Sendable {
  /// Rubber-banded model translation in points supplied by SnapDraggingModifier.
  ///
  /// The interactive spring's actual drawing can lag behind this target. The
  /// source frame used for Portal captures that drawing position separately.
  public let offset: CGSize
  /// Physical release velocity in points per second, before spring normalization.
  public let velocity: CGVector

  public init(offset: CGSize, velocity: CGVector) {
    self.offset = offset
    self.velocity = velocity
  }
}

/// Configures distance and projected velocity for a physical right reply drag.
public struct CellReplyConfiguration: Equatable, Sendable {
  /// Model distance sufficient to accept a reply without a flick.
  public let activationDistance: CGFloat
  /// Rubber-band extent beyond the activation boundary.
  public let bandLength: CGFloat
  /// Seconds of positive velocity projected for a short rightward flick.
  public let velocityProjectionDuration: CGFloat

  public init(activationDistance: CGFloat = 64, bandLength: CGFloat = 64, velocityProjectionDuration: CGFloat = 0.12) {
    precondition(activationDistance > 0 && activationDistance.isFinite)
    precondition(bandLength >= 0 && bandLength.isFinite)
    precondition(velocityProjectionDuration >= 0 && velocityProjectionDuration.isFinite)
    self.activationDistance = activationDistance
    self.bandLength = bandLength
    self.velocityProjectionDuration = velocityProjectionDuration
  }

  /// Accepts sustained distance or a sufficiently projected physical right flick.
  public func accepts(_ release: CellReplyRelease) -> Bool {
    guard release.offset.width > 0 else { return false }
    return release.offset.width + max(0, release.velocity.dx) * velocityProjectionDuration >= activationDistance
  }
}
