//
//  TiledCollectionViewLayout.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import DequeModule
import UIKit

// MARK: - TiledCollectionViewLayout

public final class TiledCollectionViewLayout: UICollectionViewLayout {

  // MARK: - Configuration

  /// Closure to query item size. Receives index and width, returns size.
  /// If nil is returned, estimatedHeight will be used.
  public var itemSizeProvider: ((_ index: Int, _ width: CGFloat) -> CGSize?)?

  /// Additional content inset to apply on top of the calculated inset.
  /// Use this to add extra space for keyboard, headers, footers, etc.
  public var additionalContentInset: UIEdgeInsets = .zero

  // MARK: - Constants

  private let virtualContentHeight: CGFloat = 100_000_000
  private let anchorY: CGFloat = 50_000_000
  private let estimatedHeight: CGFloat = 100

  // MARK: - Private State

  private var itemYPositions: Deque<CGFloat> = []
  private var itemHeights: Deque<CGFloat> = []

  // MARK: - UICollectionViewLayout Overrides

  public override var collectionViewContentSize: CGSize {
    CGSize(
      width: collectionView?.bounds.width ?? 0,
      height: virtualContentHeight
    )
  }

  public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
    collectionView?.bounds.size.width != newBounds.size.width
  }

  public override func prepare() {
    guard let collectionView else { return }
    collectionView.contentInset = calculateContentInset()
  }

  public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    guard !itemYPositions.isEmpty else { return nil }

    let boundsWidth = collectionView?.bounds.width ?? 0

    // Binary search for first visible item
    let firstIndex = findFirstVisibleIndex(in: rect)
    guard firstIndex < itemYPositions.count else { return nil }

    // Collect all visible items
    var result: [UICollectionViewLayoutAttributes] = []
    for index in firstIndex..<itemYPositions.count {
      let y = itemYPositions[index]
      let height = itemHeights[index]

      // Stop if we're past the visible rect
      if y > rect.maxY {
        break
      }

      let frame = CGRect(x: 0, y: y, width: boundsWidth, height: height)
      if frame.intersects(rect) {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
        attributes.frame = frame
        result.append(attributes)
      }
    }

    return result
  }

  public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    
    let index = indexPath.item
    
    guard index >= 0, index < itemYPositions.count else { 
      return nil 
    }

    let boundsWidth = collectionView?.bounds.width ?? 0
    let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
    attributes.frame = makeFrame(at: index, boundsWidth: boundsWidth)
    return attributes
  }

  // MARK: - Self-Sizing Support

  public override func shouldInvalidateLayout(
    forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
    withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
  ) -> Bool {
    preferredAttributes.frame.size.height != originalAttributes.frame.size.height
  }

  public override func invalidationContext(
    forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
    withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutInvalidationContext {
    
    let context = super.invalidationContext(
      forPreferredLayoutAttributes: preferredAttributes,
      withOriginalAttributes: originalAttributes
    )

    let index = preferredAttributes.indexPath.item
    let newHeight = preferredAttributes.frame.size.height

    if index < itemHeights.count {
      updateItemHeight(at: index, newHeight: newHeight)
    }

    return context
  }

  // MARK: - Public Item Management API

  public func appendItems(count: Int, startingIndex: Int) {
    let width = collectionView?.bounds.width ?? 0

    for i in 0..<count {
      let index = startingIndex + i
      let height = itemSizeProvider?(index, width)?.height ?? estimatedHeight

      let y: CGFloat
      if let lastY = itemYPositions.last, let lastHeight = itemHeights.last {
        y = lastY + lastHeight
      } else {
        y = anchorY
      }
      itemYPositions.append(y)
      itemHeights.append(height)
    }
  }

  public func prependItems(count: Int) {
    let width = collectionView?.bounds.width ?? 0

    // Process in reverse order for prepend (to insert from index 0 sequentially)
    for i in (0..<count).reversed() {
      let height = itemSizeProvider?(i, width)?.height ?? estimatedHeight
      let y = (itemYPositions.first ?? anchorY) - height
      itemYPositions.insert(y, at: 0)
      itemHeights.insert(height, at: 0)
    }
  }

  public func insertItems(count: Int, at index: Int) {
    let width = collectionView?.bounds.width ?? 0

    // Calculate the starting Y position for inserted items
    let startY: CGFloat
    if index < itemYPositions.count {
      startY = itemYPositions[index]
    } else if let lastY = itemYPositions.last, let lastHeight = itemHeights.last {
      startY = lastY + lastHeight
    } else {
      startY = anchorY
    }

    // Calculate heights and insert
    var currentY = startY
    var totalInsertedHeight: CGFloat = 0

    for i in 0..<count {
      let height = itemSizeProvider?(index + i, width)?.height ?? estimatedHeight
      itemYPositions.insert(currentY, at: index + i)
      itemHeights.insert(height, at: index + i)
      currentY += height
      totalInsertedHeight += height
    }

    // Shift all items after the insertion point
    for i in (index + count)..<itemYPositions.count {
      itemYPositions[i] += totalInsertedHeight
    }
  }

  public func removeItems(at indices: [Int]) {
    guard !indices.isEmpty else { return }

    // Sort indices in descending order to remove from end first
    let sortedIndices = indices.sorted(by: >)

    for index in sortedIndices {
      guard index >= 0, index < itemYPositions.count else { continue }

      let removedHeight = itemHeights[index]

      // Remove the item
      itemYPositions.remove(at: index)
      itemHeights.remove(at: index)

      // Shift all items after the removal point
      for i in index..<itemYPositions.count {
        itemYPositions[i] -= removedHeight
      }
    }
  }

  public func clear() {
    itemYPositions.removeAll()
    itemHeights.removeAll()
  }

  private func updateItemHeight(at index: Int, newHeight: CGFloat) {
    guard index >= 0, index < itemHeights.count else { return }

    let oldHeight = itemHeights[index]
    let heightDiff = newHeight - oldHeight

    itemHeights[index] = newHeight

    // Update Y positions for all items after this index
    for i in (index + 1)..<itemYPositions.count {
      itemYPositions[i] += heightDiff
    }
  }

  // MARK: - Private Helpers

  private func makeFrame(at index: Int, boundsWidth: CGFloat) -> CGRect {
    CGRect(
      x: 0,
      y: itemYPositions[index],
      width: boundsWidth,
      height: itemHeights[index]
    )
  }

  /// Binary search to find the first item that could be visible in the rect.
  ///
  /// Finds the smallest index where the item's bottom edge >= rect.minY.
  /// Items before this index are completely above the visible area.
  ///
  /// Example:
  /// ```
  /// items:    [0]  [1]  [2]  [3]  [4]
  /// bottom:   100  250  400  550  700
  /// rect.minY = 300
  ///
  /// Result: index 2 (first item with bottom >= 300)
  /// ```
  ///
  /// Complexity: O(log n) instead of O(n) linear search.
  private func findFirstVisibleIndex(in rect: CGRect) -> Int {
    var low = 0
    var high = itemYPositions.count

    while low < high {
      let mid = (low + high) / 2
      let itemBottom = itemYPositions[mid] + itemHeights[mid]

      if itemBottom < rect.minY {
        // Item is completely above visible area, search in right half
        low = mid + 1
      } else {
        // Item may be visible or below, search in left half
        high = mid
      }
    }

    return low
  }

  private func contentBounds() -> (top: CGFloat, bottom: CGFloat)? {
    guard let firstY = itemYPositions.first,
          let lastY = itemYPositions.last,
          let lastHeight = itemHeights.last else { return nil }
    return (firstY, lastY + lastHeight)
  }

  // MARK: - Debug Info

  /// Debug information about remaining scroll capacity.
  public struct DebugCapacityInfo {
    /// Remaining scroll space above the first item (in points).
    public let topCapacity: CGFloat
    /// Remaining scroll space below the last item (in points).
    public let bottomCapacity: CGFloat
    /// Total virtual content height.
    public let virtualHeight: CGFloat
    /// Anchor Y position (center point).
    public let anchorY: CGFloat
  }

  /// Returns debug information about remaining scroll capacity.
  /// Useful for monitoring how much virtual space remains for prepend/append operations.
  public var debugCapacityInfo: DebugCapacityInfo? {
    guard let bounds = contentBounds() else { return nil }
    return DebugCapacityInfo(
      topCapacity: bounds.top,
      bottomCapacity: virtualContentHeight - bounds.bottom,
      virtualHeight: virtualContentHeight,
      anchorY: anchorY
    )
  }

  private func calculateContentInset() -> UIEdgeInsets {
    guard let bounds = contentBounds() else { return additionalContentInset }

    let topInset = bounds.top
    let bottomInset = virtualContentHeight - bounds.bottom

    return UIEdgeInsets(
      top: -topInset + additionalContentInset.top,
      left: additionalContentInset.left,
      bottom: -bottomInset + additionalContentInset.bottom,
      right: additionalContentInset.right
    )
  }
}
