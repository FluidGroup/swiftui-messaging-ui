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

  /// Enables caching of layout attributes for better scroll performance.
  /// When enabled, attributes are reused instead of being recreated on each prepare() call.
  public var usesAttributesCache: Bool = false

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

  private var attributesCache: [IndexPath: UICollectionViewLayoutAttributes] = [:]
  private var itemYPositions: Deque<CGFloat> = []
  private var itemHeights: Deque<CGFloat> = []
  private var lastPreparedBoundsSize: CGSize = .zero
  private var needsFullAttributesRebuild: Bool = true

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

    let boundsSize = collectionView.bounds.size

    // Recalculate heights if they were added when width was 0
    if needsHeightRecalculation && boundsSize.width > 0 {
      recalculateAllHeights(width: boundsSize.width)
      needsHeightRecalculation = false
    }

    // Automatically update contentInset
    collectionView.contentInset = calculateContentInset()

    let itemCount = collectionView.numberOfItems(inSection: 0)

    // Check if we need to rebuild attributes
    let boundsSizeChanged = lastPreparedBoundsSize != boundsSize
    let shouldRebuild = !usesAttributesCache || needsFullAttributesRebuild || boundsSizeChanged

    if shouldRebuild {
      attributesCache.removeAll(keepingCapacity: usesAttributesCache)
      lastPreparedBoundsSize = boundsSize

      for index in 0..<itemCount {
        guard index < itemYPositions.count else { break }

        let indexPath = IndexPath(item: index, section: 0)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(
          x: 0,
          y: itemYPositions[index],
          width: boundsSize.width,
          height: itemHeights[index]
        )
        attributesCache[indexPath] = attributes
      }

      needsFullAttributesRebuild = false
    } else {
      // Update only frames (positions may have changed due to height updates)
      for index in 0..<itemCount {
        guard index < itemYPositions.count else { break }

        let indexPath = IndexPath(item: index, section: 0)
        if let attributes = attributesCache[indexPath] {
          attributes.frame = CGRect(
            x: 0,
            y: itemYPositions[index],
            width: boundsSize.width,
            height: itemHeights[index]
          )
        } else {
          // New item added, create attributes
          let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
          attributes.frame = CGRect(
            x: 0,
            y: itemYPositions[index],
            width: boundsSize.width,
            height: itemHeights[index]
          )
          attributesCache[indexPath] = attributes
        }
      }

      // Remove stale entries if item count decreased
      if attributesCache.count > itemCount {
        attributesCache = attributesCache.filter { $0.key.item < itemCount }
      }
    }
  }

  public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    attributesCache.values.filter { $0.frame.intersects(rect) }
  }

  public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    attributesCache[indexPath]
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

    needsFullAttributesRebuild = true
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

    needsFullAttributesRebuild = true
  }

  public func clear() {
    itemYPositions.removeAll()
    itemHeights.removeAll()
    attributesCache.removeAll()
    needsFullAttributesRebuild = true
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

    needsFullAttributesRebuild = true
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
    guard let bounds = contentBounds() else {
      return additionalContentInset
    }

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
