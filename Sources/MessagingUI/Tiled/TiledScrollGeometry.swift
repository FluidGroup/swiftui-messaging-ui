import UIKit

/// A snapshot of the scroll view's geometric state for TiledView.
///
/// Use this struct to observe scroll position changes via `onTiledScrollGeometryChange(_:)`.
/// The `pointsFromBottom` property is particularly useful for implementing "scroll to bottom" buttons
/// or auto-scroll behavior in messaging UIs.
///
/// ## Example
/// ```swift
/// TiledView(dataSource: dataSource, scrollPosition: $scrollPosition) { message, _ in
///   MessageCell(message: message)
/// }
/// .onTiledScrollGeometryChange { geometry in
///   // Show "scroll to bottom" button when user scrolls up
///   showScrollButton = geometry.pointsFromBottom > 100
/// }
/// ```
public struct TiledScrollGeometry: Equatable, Sendable {

  /// The current content offset of the scroll view.
  public var contentOffset: CGPoint

  /// The total size of the scrollable content.
  public var contentSize: CGSize

  /// The visible size of the scroll view (bounds size).
  public var visibleSize: CGSize

  /// The adjusted content inset including safe area insets.
  public var contentInset: UIEdgeInsets

  /// The distance in points from the current scroll position to the bottom edge.
  ///
  /// Returns `0` when:
  /// - The scroll view is at the bottom
  /// - The content is smaller than the visible area (no scrolling needed)
  ///
  /// Use this property to determine whether to show a "scroll to bottom" button
  /// or enable auto-scrolling when new messages arrive.
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
  ///
  /// This property captures the scroll view's state at a point in time,
  /// enabling calculations without retaining the scroll view itself.
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
