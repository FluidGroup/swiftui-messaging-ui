//
//  TiledViewCell.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import SwiftUI
import UIKit

final class TiledViewCell: UICollectionViewCell {

  static let reuseIdentifier = "TiledViewCell"

  /// Custom state for this cell
  var customState: CellState = .empty

  /// Handler called when state changes to update content
  var _updateConfigurationHandler:
    @MainActor (TiledViewCell, CellState) -> Void = { _, _ in }

  func configure<Content: View>(with content: Content, cellReveal: CellReveal? = nil) {
    contentConfiguration = UIHostingConfiguration {
      content
        .environment(\.cellReveal, cellReveal)
    }
    .margins(.all, 0)
  }

  /// Update cell content with new state
  func updateContent(using customState: CellState) {
    self.customState = customState
    _updateConfigurationHandler(self, customState)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    contentConfiguration = nil
    customState = .empty
    _updateConfigurationHandler = { _, _ in }
  }

  override func preferredLayoutAttributesFitting(
    _ layoutAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutAttributes {
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes

    // MagazineLayout方式: contentViewの幅をlayoutAttributesと同期
    if contentView.bounds.width != layoutAttributes.size.width {
      contentView.bounds.size.width = layoutAttributes.size.width
    }

    let targetSize = CGSize(
      width: layoutAttributes.frame.width,
      height: UIView.layoutFittingCompressedSize.height
    )

    let size = contentView.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )

    attributes.frame.size.height = size.height
    return attributes
  }
}
