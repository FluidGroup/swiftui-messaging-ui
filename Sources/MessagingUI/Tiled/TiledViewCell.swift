//
//  TiledViewCell.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import SwiftUI
import UIKit

final class TiledViewCell<Content: View>: UICollectionViewCell {

  static func reuseIdentifier(for kind: String) -> String {
    "\(String(reflecting: Self.self)):\(kind)"
  }

  // MARK: - Safe Area Override

  /// Override safeAreaInsets to return zero.
  /// This prevents UIHostingConfiguration from being affected by safe area changes
  /// when contentInsetAdjustmentBehavior = .never is used on the collection view.
  override var safeAreaInsets: UIEdgeInsets {
    .zero
  }

  // MARK: - Configuration

  func configure(with content: Content) {
    contentView.alpha = 1
    contentConfiguration = UIHostingConfiguration {
      content
    }
    .margins(.all, 0)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    contentView.alpha = 1
    contentConfiguration = nil
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
