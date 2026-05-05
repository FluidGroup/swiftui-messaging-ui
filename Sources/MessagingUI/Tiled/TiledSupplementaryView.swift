//
//  TiledSupplementaryView.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/20.
//

import SwiftUI
import UIKit
import ObjectiveC

extension EnvironmentValues {

  /// An action that triggers the hosting view to re-measure its intrinsic content size.
  ///
  /// Call this from within supplementary view content (header, footer, typing indicator, etc.)
  /// when a `@State` change causes the view's height to change.
  /// This is normally handled automatically by `TiledSupplementaryView`, but remains available
  /// as a fallback for custom views that do not invalidate their intrinsic content size.
  ///
  /// ## Why this is needed (workaround)
  ///
  /// Although `UIHostingController.sizingOptions = .intrinsicContentSize` ensures the hosting view's
  /// intrinsic content size stays in sync with SwiftUI content, **UICollectionView's self-sizing pipeline
  /// is pull-based** — it only calls `preferredLayoutAttributesFitting(_:)` during initial display or
  /// explicit layout invalidation. A subview's intrinsic content size change alone does not trigger
  /// the collection view to re-query the preferred size.
  ///
  /// `TiledSupplementaryView` bridges this gap automatically by observing intrinsic size invalidations
  /// from the hosted SwiftUI view and invalidating the supplementary view itself. Calling
  /// `updateSelfSizing()` manually runs the same final invalidation step.
  ///
  /// ## Pipeline
  ///
  /// 1. Hosted SwiftUI content invalidates its intrinsic content size.
  /// 2. UIKit triggers `preferredLayoutAttributesFitting(_:)` to compute the new size.
  /// 3. The layout's `invalidationContext(forPreferredLayoutAttributes:withOriginalAttributes:)` updates
  ///    the corresponding size property (e.g., `headerContentSize`) and invalidates the layout.
  ///
  /// ## Example
  ///
  /// ```swift
  /// struct ExpandableHeader: View {
  ///   @State private var isExpanded = false
  ///
  ///   var body: some View {
  ///     VStack {
  ///       Button(isExpanded ? "Show Less" : "Show More") {
  ///         isExpanded.toggle()
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
  private var isSchedulingIntrinsicContentSizeInvalidationUpdate = false
  private var isUpdatingForIntrinsicContentSizeInvalidation = false
  
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
    TiledSupplementaryIntrinsicContentSizeInvalidationObserver.install(on: hosting.view)

    addSubview(hosting.view)
    NSLayoutConstraint.activate([
      hosting.view.topAnchor.constraint(equalTo: topAnchor),
      hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    hostingController = hosting
  }

  fileprivate func didInvalidateIntrinsicContentSize(in descendant: UIView) {
    guard let hostedView = hostingController?.view else { return }
    guard descendant === hostedView || descendant.isDescendant(of: hostedView) else { return }
    guard isUpdatingForIntrinsicContentSizeInvalidation == false else { return }
    guard isSchedulingIntrinsicContentSizeInvalidationUpdate == false else { return }

    scheduleSelfSizingUpdateForIntrinsicContentSizeInvalidation()
  }

  private func scheduleSelfSizingUpdateForIntrinsicContentSizeInvalidation() {
    isSchedulingIntrinsicContentSizeInvalidationUpdate = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      self.isSchedulingIntrinsicContentSizeInvalidationUpdate = false
      guard self.hostingController?.view.superview === self else { return }

      self.isUpdatingForIntrinsicContentSizeInvalidation = true
      self.invalidateIntrinsicContentSize()
      self.isUpdatingForIntrinsicContentSizeInvalidation = false
    }
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

@MainActor
private enum TiledSupplementaryIntrinsicContentSizeInvalidationObserver {

  private static var installedClasses: Set<ObjectIdentifier> = []

  static func install(on view: UIView) {
    let viewClass: AnyClass = type(of: view)
    let classID = ObjectIdentifier(viewClass)

    guard installedClasses.contains(classID) == false else { return }

    let selector = #selector(UIView.invalidateIntrinsicContentSize)
    let originalImplementation = class_getMethodImplementation(viewClass, selector)
    typealias OriginalImplementation = @convention(c) (UIView, Selector) -> Void
    let original = unsafeBitCast(originalImplementation, to: OriginalImplementation.self)

    let block: @convention(block) (UIView) -> Void = { view in
      original(view, selector)
      view.tiled_notifySupplementaryIntrinsicContentSizeInvalidationIfNeeded()
    }

    let implementation = imp_implementationWithBlock(block)

    let added = class_addMethod(
      viewClass,
      selector,
      implementation,
      "v@:"
    )

    guard added else {
      guard classOwnsMethod(viewClass, selector),
            let method = class_getInstanceMethod(viewClass, selector) else {
        imp_removeBlock(implementation)
        assertionFailure("Failed to install TiledSupplementaryView intrinsic content size invalidation observer.")
        return
      }

      method_setImplementation(method, implementation)
      installedClasses.insert(classID)
      return
    }

    installedClasses.insert(classID)
  }

  private static func classOwnsMethod(_ viewClass: AnyClass, _ selector: Selector) -> Bool {
    var methodCount: UInt32 = 0
    guard let methods = class_copyMethodList(viewClass, &methodCount) else {
      return false
    }
    defer {
      free(methods)
    }

    for index in 0..<Int(methodCount) {
      if method_getName(methods[index]) == selector {
        return true
      }
    }

    return false
  }
}

private extension UIView {

  func tiled_notifySupplementaryIntrinsicContentSizeInvalidationIfNeeded() {
    var currentView = superview

    while let view = currentView {
      if let supplementaryView = view as? TiledSupplementaryView {
        supplementaryView.didInvalidateIntrinsicContentSize(in: self)
        return
      }

      currentView = view.superview
    }
  }
}
