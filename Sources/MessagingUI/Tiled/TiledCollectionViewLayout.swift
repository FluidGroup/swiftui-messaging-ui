//
//  TiledCollectionViewLayout.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import UIKit

// MARK: - TiledCollectionViewLayout

public final class TiledCollectionViewLayout: UICollectionViewLayout {

  private var itemAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
  private var itemYPositions: [CGFloat] = []
  private var itemHeights: [CGFloat] = []

  private let virtualContentHeight: CGFloat = 100_000_000
  private let anchorY: CGFloat = 50_000_000

  public override var collectionViewContentSize: CGSize {
    CGSize(
      width: collectionView?.bounds.width ?? 0,
      height: virtualContentHeight
    )
  }

  public override func prepare() {
    guard let collectionView else { return }
    itemAttributes.removeAll()

    let itemCount = collectionView.numberOfItems(inSection: 0)

    for index in 0..<itemCount {
      guard index < itemYPositions.count else { break }

      let indexPath = IndexPath(item: index, section: 0)
      let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
      attributes.frame = CGRect(
        x: 0,
        y: itemYPositions[index],
        width: collectionView.bounds.width,
        height: itemHeights[index]
      )
      itemAttributes[indexPath] = attributes
    }
  }

  public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    itemAttributes.values.filter { $0.frame.intersects(rect) }
  }

  public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    itemAttributes[indexPath]
  }

  public func appendItems(heights: [CGFloat]) {
    for height in heights {
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

  public func prependItems(heights: [CGFloat]) {
    for height in heights.reversed() {
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
    itemAttributes.removeAll()
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
