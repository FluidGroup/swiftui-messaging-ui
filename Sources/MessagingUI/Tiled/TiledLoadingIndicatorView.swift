//
//  TiledLoadingIndicatorView.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/20.
//

import SwiftUI
import UIKit

/// Supplementary view for displaying loading indicators and typing indicator at list edges.
final class TiledLoadingIndicatorView: UICollectionReusableView {

  static let headerKind = "TiledLoadingIndicatorHeader"
  static let footerKind = "TiledLoadingIndicatorFooter"
  static let typingIndicatorKind = "TiledTypingIndicator"
  static let reuseIdentifier = "TiledLoadingIndicatorView"

  private var hostingController: UIHostingController<AnyView>?

  func configure<Content: View>(with content: Content) {
    // Remove existing hosting controller if present
    hostingController?.view.removeFromSuperview()
    hostingController?.removeFromParent()

    let hosting = UIHostingController(rootView: AnyView(content))
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    hosting.view.backgroundColor = .clear

    addSubview(hosting.view)
    NSLayoutConstraint.activate([
      hosting.view.topAnchor.constraint(equalTo: topAnchor),
      hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    hostingController = hosting
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    hostingController?.view.removeFromSuperview()
    hostingController?.removeFromParent()
    hostingController = nil
  }

  override func preferredLayoutAttributesFitting(
    _ layoutAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutAttributes {
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes

    if bounds.width != layoutAttributes.size.width {
      bounds.size.width = layoutAttributes.size.width
    }

    let targetSize = CGSize(
      width: layoutAttributes.frame.width,
      height: UIView.layoutFittingCompressedSize.height
    )

    let size = systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )

    attributes.frame.size.height = size.height
    return attributes
  }
}
