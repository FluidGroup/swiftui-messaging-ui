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

  /// Closure to query item counts for each visual section in layout order.
  var sectionItemCountsProvider: (() -> [Int])?

  /// Additional content inset to apply on top of the calculated inset.
  /// Use this to add extra space for keyboard, headers, footers, etc.
  public var additionalContentInset: UIEdgeInsets = .zero

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
  /// Metrics from before a batch mutation. UICollectionView can ask for
  /// old-count attributes while our data source already exposes the new items.
  private var batchUpdateMetrics: ItemMetrics?

  /// Tracks whether item heights need recalculation due to width being 0 at initial add time.
  private var needsHeightRecalculation: Bool = false

  /// Edge content that should keep its cell height but not expand the scrollable content bounds.
  var hiddenEdgeContentInset: UIEdgeInsets = .zero {
    didSet {
      guard hiddenEdgeContentInset != oldValue else { return }
      invalidateLayout()
    }
  }

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

    let metrics = activeItemMetrics()
    let itemCount = metrics.count

    // Add cell items
    if itemCount > 0 {
      // Binary search for first visible item
      let firstIndex = findFirstVisibleIndex(in: rect, metrics: metrics)

      if firstIndex < itemCount {
        for index in firstIndex..<itemCount {
          let y = metrics.yPositions[index]

          // Stop if we're past the visible rect
          if y > rect.maxY {
            break
          }

          let height = metrics.heights[index]
          let frame = CGRect(x: 0, y: y, width: boundsWidth, height: height)

          if frame.intersects(rect) {
            if let indexPath = indexPath(forLinearIndex: index, in: metrics) {
              let attributes = getOrCreateAttributes(for: indexPath, frame: frame)
              result.append(attributes)
            }
          }
        }
      }
    }

    return result
  }

  public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    let metrics = activeItemMetrics()

    guard let index = linearIndex(for: indexPath, in: metrics) else { return nil }

    let boundsWidth = collectionView?.bounds.width ?? 0
    let frame = CGRect(
      x: 0,
      y: metrics.yPositions[index],
      width: boundsWidth,
      height: metrics.heights[index]
    )

    return getOrCreateAttributes(for: indexPath, frame: frame)
  }

  /// Gets cached attributes or creates new ones (IGListKit-style on-demand caching).
  private func getOrCreateAttributes(for indexPath: IndexPath, frame: CGRect) -> UICollectionViewLayoutAttributes {
    if batchUpdateMetrics != nil {
      let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
      attributes.frame = frame
      return attributes
    }

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

    let newHeight = preferredAttributes.frame.size.height

    if preferredAttributes.representedElementCategory == .cell {
      if let index = linearIndex(for: preferredAttributes.indexPath, in: currentItemMetrics()),
         index < itemHeights.count {
        updateItemHeight(at: index, newHeight: newHeight)
      }
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

  func insertItemsBeforeKeepingTrailingPositions(count: Int, at index: Int) {
    guard count > 0 else { return }

    let width = collectionView?.bounds.width ?? 0
    let insertionIndex = max(0, min(index, itemYPositions.count))

    if width == 0 {
      needsHeightRecalculation = true
    }

    let heights = (0..<count).map { offset in
      itemSizeProvider?(insertionIndex + offset, width)?.height ?? estimatedHeight
    }
    let totalInsertedHeight = heights.reduce(0, +)

    let insertionEndY: CGFloat
    if insertionIndex < itemYPositions.count {
      insertionEndY = itemYPositions[insertionIndex]
    } else if let lastY = itemYPositions.last, let lastHeight = itemHeights.last {
      insertionEndY = lastY + lastHeight
    } else {
      insertionEndY = anchorY
    }

    for i in 0..<insertionIndex {
      itemYPositions[i] -= totalInsertedHeight
    }

    var currentY = insertionEndY - totalInsertedHeight
    for (offset, height) in heights.enumerated() {
      itemYPositions.insert(currentY, at: insertionIndex + offset)
      itemHeights.insert(height, at: insertionIndex + offset)
      currentY += height
    }

    invalidateAttributesCache()
    logCapacity(operation: "insertItemsBeforeKeepingTrailingPositions")
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

  func removeItemsKeepingTrailingPositions(at indices: [Int]) {
    guard !indices.isEmpty else { return }

    let sortedIndices = indices.sorted(by: >)

    for index in sortedIndices {
      guard index >= 0, index < itemYPositions.count else { continue }

      let removedHeight = itemHeights[index]

      itemYPositions.remove(at: index)
      itemHeights.remove(at: index)

      for i in 0..<index {
        itemYPositions[i] += removedHeight
      }
    }

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

  func beginBatchUpdates() {
    batchUpdateMetrics = currentItemMetrics()
  }

  func endBatchUpdates() {
    batchUpdateMetrics = nil
    invalidateLayout()
  }

  /// Invalidates the attributes cache. Call when IndexPaths change.
  private func invalidateAttributesCache() {
    attributesCache.removeAll(keepingCapacity: true)
  }

  public func updateItemHeight(at index: Int, newHeight: CGFloat) {
    guard index >= 0, index < itemHeights.count else { return }

    let oldHeight = itemHeights[index]
    let heightDiff = newHeight - oldHeight
    guard heightDiff != 0 else { return }

    itemHeights[index] = newHeight

    // Update Y positions for all items after this index
    for i in (index + 1)..<itemYPositions.count {
      itemYPositions[i] += heightDiff
    }

    invalidateAttributesCache()
  }

  func updateItemHeightKeepingTrailingPositions(at index: Int, newHeight: CGFloat) {
    guard index >= 0, index < itemHeights.count else { return }

    let oldHeight = itemHeights[index]
    let heightDiff = newHeight - oldHeight
    guard heightDiff != 0 else { return }

    itemHeights[index] = newHeight
    itemYPositions[index] -= heightDiff

    for i in 0..<index {
      itemYPositions[i] -= heightDiff
    }

    invalidateAttributesCache()
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
  private func findFirstVisibleIndex(in rect: CGRect, metrics: ItemMetrics) -> Int {
    var low = 0
    var high = metrics.count

    while low < high {
      let mid = (low + high) / 2
      let itemBottom = metrics.yPositions[mid] + metrics.heights[mid]

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

  private struct ItemMetrics {
    var yPositions: Deque<CGFloat>
    var heights: Deque<CGFloat>
    var sectionItemCounts: [Int]

    var count: Int {
      min(yPositions.count, heights.count)
    }
  }

  private func currentItemMetrics() -> ItemMetrics {
    ItemMetrics(
      yPositions: itemYPositions,
      heights: itemHeights,
      sectionItemCounts: currentSectionItemCounts()
    )
  }

  private func activeItemMetrics() -> ItemMetrics {
    let currentMetrics = currentItemMetrics()

    guard let batchUpdateMetrics,
          let collectionView,
          collectionView.numberOfSections > 0 else {
      return currentMetrics
    }

    if observedItemCount(in: collectionView) == batchUpdateMetrics.count {
      return batchUpdateMetrics
    } else {
      return currentMetrics
    }
  }

  private func currentSectionItemCounts() -> [Int] {
    let counts = sectionItemCountsProvider?() ?? [itemYPositions.count]
    guard counts.reduce(0, +) == itemYPositions.count else {
      return [itemYPositions.count]
    }
    return counts
  }

  private func observedItemCount(in collectionView: UICollectionView) -> Int {
    guard collectionView.numberOfSections > 0 else { return 0 }
    return (0..<collectionView.numberOfSections).reduce(0) { partialResult, section in
      partialResult + collectionView.numberOfItems(inSection: section)
    }
  }

  private func linearIndex(for indexPath: IndexPath, in metrics: ItemMetrics) -> Int? {
    guard indexPath.section >= 0,
          indexPath.section < metrics.sectionItemCounts.count else {
      return nil
    }

    let itemCount = metrics.sectionItemCounts[indexPath.section]
    guard indexPath.item >= 0, indexPath.item < itemCount else {
      return nil
    }

    let precedingCount = metrics.sectionItemCounts[..<indexPath.section].reduce(0, +)
    let index = precedingCount + indexPath.item
    guard index < metrics.count else { return nil }
    return index
  }

  private func indexPath(forLinearIndex linearIndex: Int, in metrics: ItemMetrics) -> IndexPath? {
    guard linearIndex >= 0, linearIndex < metrics.count else { return nil }

    var remainingIndex = linearIndex
    for (section, itemCount) in metrics.sectionItemCounts.enumerated() {
      if remainingIndex < itemCount {
        return IndexPath(item: remainingIndex, section: section)
      }
      remainingIndex -= itemCount
    }

    return nil
  }

  private func contentBounds(in metrics: ItemMetrics) -> (top: CGFloat, bottom: CGFloat)? {
    guard let firstY = metrics.yPositions.first,
          let lastY = metrics.yPositions.last,
          let lastHeight = metrics.heights.last else { return nil }
    return (firstY, lastY + lastHeight)
  }

  private func logCapacity(operation: String) {
    guard let bounds = contentBounds(in: currentItemMetrics()) else { return }

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
    guard let bounds = contentBounds(in: currentItemMetrics()) else { return nil }
    return DebugCapacityInfo(
      topCapacity: bounds.top,
      bottomCapacity: virtualContentHeight - bounds.bottom,
      virtualHeight: virtualContentHeight,
      anchorY: anchorY
    )
  }

  private func calculateContentInset() -> UIEdgeInsets {
    guard let bounds = contentBounds(in: activeItemMetrics()) else {
      // Empty list: treat anchorY as bottom position to appear "at bottom"
      let topInset = anchorY + hiddenEdgeContentInset.top
      let bottomInset = virtualContentHeight - (anchorY - hiddenEdgeContentInset.bottom)
      return UIEdgeInsets(
        top: -topInset + additionalContentInset.top,
        left: additionalContentInset.left,
        bottom: -bottomInset + additionalContentInset.bottom,
        right: additionalContentInset.right
      )
    }

    let topInset = bounds.top + hiddenEdgeContentInset.top
    let bottomInset = virtualContentHeight - (bounds.bottom - hiddenEdgeContentInset.bottom)

    return UIEdgeInsets(
      top: -topInset + additionalContentInset.top,
      left: additionalContentInset.left,
      bottom: -bottomInset + additionalContentInset.bottom,
      right: additionalContentInset.right
    )
  }
}
