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

  /// Size of the header supplementary view (loading indicator at top)
  public var headerSize: CGSize = .zero

  /// Size of the footer supplementary view (loading indicator at bottom)
  public var footerSize: CGSize = .zero

  /// Size of the typing indicator supplementary view (between last item and footer)
  public var typingIndicatorSize: CGSize = .zero

  // MARK: - Constants

  private let virtualContentHeight: CGFloat = 100_000_000
  private let anchorY: CGFloat = 50_000_000
  private let estimatedHeight: CGFloat = 100

  // MARK: - Private State

  /// On-demand cache for layout attributes (IGListKit-style).
  /// Attributes are created when requested and cached for reuse.
  private var attributesCache: [IndexPath: UICollectionViewLayoutAttributes] = [:]
  private var itemYPositions: Deque<CGFloat> = []
  private var itemHeights: Deque<CGFloat> = []
  private var lastPreparedBoundsWidth: CGFloat = 0

  /// Tracks whether item heights need recalculation due to width being 0 at initial add time.
  private var needsHeightRecalculation: Bool = false

  // MARK: - UICollectionViewLayout Overrides

  public override var collectionViewContentSize: CGSize {
    CGSize(
      width: collectionView?.bounds.width ?? 0,
      height: virtualContentHeight
    )
  }

  public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
    collectionView?.bounds.size != newBounds.size
  }

  public override func prepare() {
    guard let collectionView else { return }

    let boundsWidth = collectionView.bounds.width

    // Recalculate heights if they were added when width was 0
    if needsHeightRecalculation && boundsWidth > 0 {
      recalculateAllHeights(width: boundsWidth)
      needsHeightRecalculation = false
    }

    // Invalidate cache if width changed
    if lastPreparedBoundsWidth != boundsWidth {
      attributesCache.removeAll(keepingCapacity: true)
      lastPreparedBoundsWidth = boundsWidth
    }

    // Automatically update contentInset
    collectionView.contentInset = calculateContentInset()
  }

  public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    var result: [UICollectionViewLayoutAttributes] = []

    let boundsWidth = collectionView?.bounds.width ?? 0

    // Add header supplementary view if visible
    if headerSize.height > 0 {
      if let headerAttrs = layoutAttributesForSupplementaryView(
        ofKind: TiledLoadingIndicatorView.headerKind,
        at: IndexPath(item: 0, section: 0)
      ), headerAttrs.frame.intersects(rect) {
        result.append(headerAttrs)
      }
    }

    // Add cell items
    if !itemYPositions.isEmpty {
      // Binary search for first visible item
      let firstIndex = findFirstVisibleIndex(in: rect)

      if firstIndex < itemYPositions.count {
        for index in firstIndex..<itemYPositions.count {
          let y = itemYPositions[index]

          // Stop if we're past the visible rect
          if y > rect.maxY {
            break
          }

          let height = itemHeights[index]
          let frame = CGRect(x: 0, y: y, width: boundsWidth, height: height)

          if frame.intersects(rect) {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = getOrCreateAttributes(for: indexPath, frame: frame)
            result.append(attributes)
          }
        }
      }
    }

    // Add typing indicator supplementary view if visible
    if typingIndicatorSize.height > 0 {
      if let typingAttrs = layoutAttributesForSupplementaryView(
        ofKind: TiledLoadingIndicatorView.typingIndicatorKind,
        at: IndexPath(item: 0, section: 0)
      ), typingAttrs.frame.intersects(rect) {
        result.append(typingAttrs)
      }
    }

    // Add footer supplementary view if visible
    if footerSize.height > 0 {
      if let footerAttrs = layoutAttributesForSupplementaryView(
        ofKind: TiledLoadingIndicatorView.footerKind,
        at: IndexPath(item: 0, section: 0)
      ), footerAttrs.frame.intersects(rect) {
        result.append(footerAttrs)
      }
    }

    return result
  }

  public override func layoutAttributesForSupplementaryView(
    ofKind elementKind: String,
    at indexPath: IndexPath
  ) -> UICollectionViewLayoutAttributes? {
    let boundsWidth = collectionView?.bounds.width ?? 0

    switch elementKind {
    case TiledLoadingIndicatorView.headerKind:
      guard headerSize.height > 0 else { return nil }
      let attrs = UICollectionViewLayoutAttributes(
        forSupplementaryViewOfKind: elementKind,
        with: indexPath
      )
      // Position header above first item (or at anchorY if empty)
      let topY = itemYPositions.first ?? anchorY
      attrs.frame = CGRect(
        x: 0,
        y: topY - headerSize.height,
        width: boundsWidth,
        height: headerSize.height
      )
      return attrs

    case TiledLoadingIndicatorView.typingIndicatorKind:
      guard typingIndicatorSize.height > 0 else { return nil }
      let attrs = UICollectionViewLayoutAttributes(
        forSupplementaryViewOfKind: elementKind,
        with: indexPath
      )
      // Position typing indicator below last item (or at anchorY if empty)
      let bottomY: CGFloat
      if let lastY = itemYPositions.last, let lastH = itemHeights.last {
        bottomY = lastY + lastH
      } else {
        bottomY = anchorY
      }
      attrs.frame = CGRect(
        x: 0,
        y: bottomY,
        width: boundsWidth,
        height: typingIndicatorSize.height
      )
      return attrs

    case TiledLoadingIndicatorView.footerKind:
      guard footerSize.height > 0 else { return nil }
      let attrs = UICollectionViewLayoutAttributes(
        forSupplementaryViewOfKind: elementKind,
        with: indexPath
      )
      // Position footer below typing indicator (or last item, or anchorY if empty)
      var bottomY: CGFloat
      if let lastY = itemYPositions.last, let lastH = itemHeights.last {
        bottomY = lastY + lastH
      } else {
        bottomY = anchorY
      }
      // Add typing indicator height if visible
      if typingIndicatorSize.height > 0 {
        bottomY += typingIndicatorSize.height
      }
      attrs.frame = CGRect(
        x: 0,
        y: bottomY,
        width: boundsWidth,
        height: footerSize.height
      )
      return attrs

    default:
      return nil
    }
  }

  public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    let index = indexPath.item

    // Return frameless attributes for out-of-bounds indices to avoid UICollectionView crashes
    guard index >= 0, index < itemYPositions.count else {
      return UICollectionViewLayoutAttributes(forCellWith: indexPath)
    }

    let boundsWidth = collectionView?.bounds.width ?? 0
    let frame = CGRect(
      x: 0,
      y: itemYPositions[index],
      width: boundsWidth,
      height: itemHeights[index]
    )

    return getOrCreateAttributes(for: indexPath, frame: frame)
  }

  /// Gets cached attributes or creates new ones (IGListKit-style on-demand caching).
  private func getOrCreateAttributes(for indexPath: IndexPath, frame: CGRect) -> UICollectionViewLayoutAttributes {
    if let cached = attributesCache[indexPath] {
      // Update frame in case position changed
      cached.frame = frame
      return cached
    }

    let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
    attributes.frame = frame
    attributesCache[indexPath] = attributes
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

    // If width is 0, mark for recalculation in prepare()
    if width == 0 {
      needsHeightRecalculation = true
    }

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

    logCapacity(operation: "appendItems")
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

    // Invalidate cache since IndexPaths shifted
    invalidateAttributesCache()

    logCapacity(operation: "prependItems")
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

    // Invalidate cache since IndexPaths shifted
    invalidateAttributesCache()
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

    // Invalidate cache since IndexPaths shifted
    invalidateAttributesCache()
  }

  public func clear() {
    itemYPositions.removeAll()
    itemHeights.removeAll()
    invalidateAttributesCache()
  }

  /// Invalidates the attributes cache. Call when IndexPaths change.
  private func invalidateAttributesCache() {
    attributesCache.removeAll(keepingCapacity: true)
  }

  public func updateItemHeight(at index: Int, newHeight: CGFloat) {
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

  /// Recalculates all item heights and Y positions when width becomes available.
  private func recalculateAllHeights(width: CGFloat) {
    guard !itemYPositions.isEmpty else { return }

    var currentY = anchorY

    for index in 0..<itemYPositions.count {
      let height = itemSizeProvider?(index, width)?.height ?? estimatedHeight
      itemYPositions[index] = currentY
      itemHeights[index] = height
      currentY += height
    }

    invalidateAttributesCache()
  }

  /// Binary search to find the first item that could be visible in the rect.
  ///
  /// Finds the smallest index where the item's bottom edge >= rect.minY.
  /// Items before this index are completely above the visible area.
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

  private func logCapacity(operation: String) {
    guard let bounds = contentBounds() else { return }

    let topPercent = (bounds.top / anchorY) * 100
    let bottomPercent = ((virtualContentHeight - bounds.bottom) / (virtualContentHeight - anchorY)) * 100

    Log.layout.debug("\(operation): top=\(topPercent, format: .fixed(precision: 1))%, bottom=\(bottomPercent, format: .fixed(precision: 1))%")
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
    guard let bounds = contentBounds() else {
      // Empty list: treat anchorY as bottom position to appear "at bottom"
      // Account for header/footer/typingIndicator if present
      var topY = anchorY
      var bottomY = anchorY

      if headerSize.height > 0 {
        topY -= headerSize.height
      }
      if typingIndicatorSize.height > 0 {
        bottomY += typingIndicatorSize.height
      }
      if footerSize.height > 0 {
        bottomY += footerSize.height
      }

      let topInset = topY
      let bottomInset = virtualContentHeight - bottomY
      return UIEdgeInsets(
        top: -topInset + additionalContentInset.top,
        left: additionalContentInset.left,
        bottom: -bottomInset + additionalContentInset.bottom,
        right: additionalContentInset.right
      )
    }

    // Adjust bounds to include header/footer/typingIndicator
    var topY = bounds.top
    var bottomY = bounds.bottom

    if headerSize.height > 0 {
      topY -= headerSize.height
    }
    if typingIndicatorSize.height > 0 {
      bottomY += typingIndicatorSize.height
    }
    if footerSize.height > 0 {
      bottomY += footerSize.height
    }

    let topInset = topY
    let bottomInset = virtualContentHeight - bottomY

    return UIEdgeInsets(
      top: -topInset + additionalContentInset.top,
      left: additionalContentInset.left,
      bottom: -bottomInset + additionalContentInset.bottom,
      right: additionalContentInset.right
    )
  }
}
