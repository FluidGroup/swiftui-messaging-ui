//
//  TiledSupplementaryView.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/20.
//

import SwiftUI
import UIKit

extension EnvironmentValues {

  /// An action that triggers the hosting view to re-measure its intrinsic content size.
  ///
  /// Call this from within supplementary view content (header, footer, typing indicator, etc.)
  /// when a `@State` change causes the view's height to change.
  /// Without calling this, the collection view layout will not be notified of the size change
  /// and the view may clip or leave empty space.
  ///
  /// ## Why this is needed (workaround)
  ///
  /// Although `UIHostingController.sizingOptions = .intrinsicContentSize` ensures the hosting view's
  /// intrinsic content size stays in sync with SwiftUI content, **UICollectionView's self-sizing pipeline
  /// is pull-based** — it only calls `preferredLayoutAttributesFitting(_:)` during initial display or
  /// explicit layout invalidation. A subview's intrinsic content size change alone does not trigger
  /// the collection view to re-query the preferred size.
  ///
  /// Calling `updateSelfSizing()` bridges this gap by invoking `invalidateIntrinsicContentSize()` on
  /// the `UICollectionReusableView` itself, which tells UICollectionView to re-run the self-sizing pipeline.
  ///
  /// ## Pipeline
  ///
  /// 1. Calling `updateSelfSizing()` invokes `invalidateIntrinsicContentSize()` on the hosting view.
  /// 2. UIKit triggers `preferredLayoutAttributesFitting(_:)` to compute the new size.
  /// 3. The layout's `invalidationContext(forPreferredLayoutAttributes:withOriginalAttributes:)` updates
  ///    the corresponding size property (e.g., `headerContentSize`) and invalidates the layout.
  ///
  /// ## Example
  ///
  /// ```swift
  /// struct ExpandableHeader: View {
  ///   @State private var isExpanded = false
  ///   @Environment(\.updateSelfSizing) private var updateSelfSizing
  ///
  ///   var body: some View {
  ///     VStack {
  ///       Button(isExpanded ? "Show Less" : "Show More") {
  ///         isExpanded.toggle()
  ///         updateSelfSizing()
  ///       }
  ///       if isExpanded {
  ///         Text("Additional content here")
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// - Note: This is a no-op by default. It is only wired up when the view is hosted
  ///   inside a ``TiledSupplementaryView``.
  @Entry public var updateSelfSizing: () -> Void = {}
}

/// Generic supplementary view for hosting SwiftUI content in collection view supplementary positions.
final class TiledSupplementaryView: UICollectionReusableView {

  static let headerKind = "TiledLoadingIndicatorHeader"
  static let footerKind = "TiledLoadingIndicatorFooter"
  static let typingIndicatorKind = "TiledTypingIndicator"
  static let contentHeaderKind = "TiledContentHeader"
  static let reuseIdentifier = "TiledSupplementaryView"

  private var hostingController: UIHostingController<AnyView>?
  
  /// Override safeAreaInsets to return zero. This prevents UIHostingConfiguration from being affected by safe area changes when contentInsetAdjustmentBehavior = .never is used on the collection view.
  override var safeAreaInsets: UIEdgeInsets {
    .zero
  }

  func configure<Content: View>(with content: Content) {
    // Remove existing hosting controller if present
    hostingController?.view.removeFromSuperview()
    hostingController?.removeFromParent()

    let hosting = UIHostingController(rootView: AnyView(content.environment(\.updateSelfSizing) { [weak self] in
      guard let self = self else { return }
      // Trigger layout update when content changes
      self.invalidateIntrinsicContentSize()
    }))
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    hosting.sizingOptions = .intrinsicContentSize
    hosting.view.backgroundColor = .clear
    hosting.safeAreaRegions = []

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
