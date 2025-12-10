//
//  TiledCollectionViewLayout.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import UIKit

// MARK: - TiledCollectionViewLayout

public final class TiledCollectionViewLayout: UICollectionViewLayout {

  // MARK: - Configuration

  /// Enables caching of layout attributes for better scroll performance.
  /// When enabled, attributes are reused instead of being recreated on each prepare() call.
  public var usesAttributesCache: Bool = true

  /// サイズを問い合わせるclosure。indexとwidthを渡し、サイズを返す。
  /// nilを返した場合はestimatedHeightを使用。
  public var itemSizeProvider: ((_ index: Int, _ width: CGFloat) -> CGSize?)?

  // MARK: - Private Properties

  private var attributesCache: [IndexPath: UICollectionViewLayoutAttributes] = [:]
  private var itemYPositions: [CGFloat] = []
  private var itemHeights: [CGFloat] = []
  private var lastPreparedBoundsSize: CGSize = .zero
  private var needsFullAttributesRebuild: Bool = true

  private let virtualContentHeight: CGFloat = 100_000_000
  private let anchorY: CGFloat = 50_000_000

  public override var collectionViewContentSize: CGSize {
    CGSize(
      width: collectionView?.bounds.width ?? 0,
      height: virtualContentHeight
    )
  }

//  public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
//    collectionView?.bounds.size != newBounds.size
//  }

  public override func prepare() {
    guard let collectionView else { return }

    // contentInsetを自動更新
    collectionView.contentInset = calculateContentInset()

    let boundsSize = collectionView.bounds.size
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

  private let estimatedHeight: CGFloat = 100

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

    // prependは逆順で処理（index 0から順に挿入するため）
    for i in (0..<count).reversed() {
      let height = itemSizeProvider?(i, width)?.height ?? estimatedHeight
      let y = (itemYPositions.first ?? anchorY) - height
      itemYPositions.insert(y, at: 0)
      itemHeights.insert(height, at: 0)
    }
  }

  public func firstItemY() -> CGFloat? {
    itemYPositions.first
  }

  public func contentBounds() -> (top: CGFloat, bottom: CGFloat)? {
    guard let firstY = itemYPositions.first,
          let lastY = itemYPositions.last,
          let lastHeight = itemHeights.last else { return nil }
    return (firstY, lastY + lastHeight)
  }

  public func calculateContentInset() -> UIEdgeInsets {
    guard let bounds = contentBounds() else { return .zero }

    let topInset = bounds.top
    let bottomInset = virtualContentHeight - bounds.bottom

    return UIEdgeInsets(
      top: -topInset,
      left: 0,
      bottom: -bottomInset,
      right: 0
    )
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
}
