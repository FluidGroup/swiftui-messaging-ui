import UIKit

public struct TiledScrollGeometry: Equatable, Sendable {

  /// Raw values
  public var contentOffset: CGPoint
  public var contentSize: CGSize
  public var visibleSize: CGSize
  public var contentInset: UIEdgeInsets

  /// Computed: distance from bottom edge
  public var pointsFromBottom: CGFloat {
    // Content smaller than view = no scrolling needed = always at bottom
    guard contentSize.height > visibleSize.height else { return 0 }

    let maxOffsetY = contentSize.height - visibleSize.height + contentInset.bottom
    return max(0, maxOffsetY - contentOffset.y)
  }

  public init(
    contentOffset: CGPoint,
    contentSize: CGSize,
    visibleSize: CGSize,
    contentInset: UIEdgeInsets
  ) {
    self.contentOffset = contentOffset
    self.contentSize = contentSize
    self.visibleSize = visibleSize
    self.contentInset = contentInset
  }
}

// MARK: - UIScrollView Extension

extension UIScrollView {

  /// Returns a snapshot of the scroll view's current geometric state.
  @MainActor
  var tiledScrollGeometry: TiledScrollGeometry {
    TiledScrollGeometry(
      contentOffset: contentOffset,
      contentSize: contentSize,
      visibleSize: bounds.size,
      contentInset: adjustedContentInset
    )
  }
}
