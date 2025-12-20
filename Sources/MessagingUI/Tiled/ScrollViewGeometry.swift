//
//  ScrollViewGeometry.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/21.
//

import UIKit

/// Represents the geometric state of a scroll view for scroll calculations.
///
/// This struct extracts the essential properties needed to calculate scroll positions,
/// enabling pure function implementations that can be unit tested without UIScrollView.
public struct ScrollViewGeometry: Equatable, Sendable {
  public let contentSize: CGSize
  public let contentOffset: CGPoint
  public let bounds: CGSize
  public let adjustedContentInset: UIEdgeInsets

  public init(
    contentSize: CGSize,
    contentOffset: CGPoint,
    bounds: CGSize,
    adjustedContentInset: UIEdgeInsets
  ) {
    self.contentSize = contentSize
    self.contentOffset = contentOffset
    self.bounds = bounds
    self.adjustedContentInset = adjustedContentInset
  }

  /// Calculates the content offset needed to make a rect visible.
  ///
  /// This is a pure function reimplementation of `UIScrollView.scrollRectToVisible(_:animated:)`
  /// that can be unit tested without UIScrollView.
  ///
  /// - Parameter rect: The rect to make visible in content coordinates
  /// - Returns: The new content offset, or `nil` if no scrolling is needed
  public func contentOffsetToMakeRectVisible(_ rect: CGRect) -> CGPoint? {
    // 1. Check if scrolling is possible
    let visibleHeight = bounds.height
      - adjustedContentInset.top
      - adjustedContentInset.bottom

    guard contentSize.height > visibleHeight else {
      // Content is smaller than visible area - no scrolling needed
      return nil
    }

    // 2. Calculate current visible rect
    let visibleRect = CGRect(
      x: contentOffset.x,
      y: contentOffset.y + adjustedContentInset.top,
      width: bounds.width,
      height: visibleHeight
    )

    // 3. Check if rect is already fully visible
    if visibleRect.contains(rect) {
      return nil
    }

    // 4. Calculate new offset (minimum scroll to make rect visible)
    var newOffsetY = contentOffset.y

    if rect.maxY > visibleRect.maxY {
      // Rect extends below visible area - scroll down
      newOffsetY += rect.maxY - visibleRect.maxY
    } else if rect.minY < visibleRect.minY {
      // Rect extends above visible area - scroll up
      newOffsetY -= visibleRect.minY - rect.minY
    }

    // 5. Clamp offset to valid range
    let minOffsetY = -adjustedContentInset.top
    let maxOffsetY = contentSize.height
      - bounds.height
      + adjustedContentInset.bottom
    newOffsetY = max(minOffsetY, min(maxOffsetY, newOffsetY))

    let newOffset = CGPoint(x: contentOffset.x, y: newOffsetY)

    // 6. Return nil if no change needed
    guard newOffset != contentOffset else {
      return nil
    }

    return newOffset
  }
}

// MARK: - UIScrollView Extension

extension UIScrollView {

  /// Returns a snapshot of the scroll view's current geometric state.
  ///
  /// Use this to perform scroll calculations without retaining the scroll view.
  @MainActor
  var scrollViewGeometry: ScrollViewGeometry {
    ScrollViewGeometry(
      contentSize: contentSize,
      contentOffset: contentOffset,
      bounds: bounds.size,
      adjustedContentInset: adjustedContentInset
    )
  }
}
