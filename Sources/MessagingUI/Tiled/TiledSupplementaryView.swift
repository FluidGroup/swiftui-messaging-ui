//
//  TiledSupplementaryView.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/20.
//

import SwiftUI
import UIKit
import ObjectiveC

enum TiledSupplementaryViewKind {

  static let headerKind = "TiledLoadingIndicatorHeader"
  static let footerKind = "TiledLoadingIndicatorFooter"
  static let typingIndicatorKind = "TiledTypingIndicator"
  static let contentHeaderKind = "TiledContentHeader"
}

@MainActor
private protocol TiledSupplementaryIntrinsicContentSizeInvalidationTarget: UICollectionReusableView {

  func didInvalidateIntrinsicContentSize(in descendant: UIView)
}

private struct TiledSupplementaryHostingContent<Content: View>: View {

  let content: Content

  var body: some View {
    content
  }
}

/// Generic supplementary view for hosting SwiftUI content in collection view supplementary positions.
final class TiledSupplementaryView<Content: View>: UICollectionReusableView, TiledSupplementaryIntrinsicContentSizeInvalidationTarget {

  static func reuseIdentifier(for kind: String) -> String {
    "\(String(reflecting: Self.self)):\(kind)"
  }

  private var hostingController: UIHostingController<TiledSupplementaryHostingContent<Content>>?
  private var isSchedulingIntrinsicContentSizeInvalidationUpdate = false
  private var isUpdatingForIntrinsicContentSizeInvalidation = false
  private var currentLayoutAttributes: UICollectionViewLayoutAttributes?

  func configure(with content: Content) {
    let hostingContent = TiledSupplementaryHostingContent(
      content: content
    )

    if let hostingController {
      hostingController.rootView = hostingContent
      return
    }

    let hostingController = UIHostingController(rootView: hostingContent)
    hostingController.sizingOptions = .intrinsicContentSize
    hostingController.safeAreaRegions = []
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.backgroundColor = .clear
    TiledSupplementaryIntrinsicContentSizeInvalidationObserver.install(on: hostingController.view)

    addSubview(hostingController.view)
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    self.hostingController = hostingController
  }

  func didInvalidateIntrinsicContentSize(in descendant: UIView) {
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
      self.invalidateOwnSupplementaryLayout()
      self.isUpdatingForIntrinsicContentSizeInvalidation = false
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    isSchedulingIntrinsicContentSizeInvalidationUpdate = false
    isUpdatingForIntrinsicContentSizeInvalidation = false
    currentLayoutAttributes = nil
  }

  override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
    super.apply(layoutAttributes)
    currentLayoutAttributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes
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

  private func invalidateOwnSupplementaryLayout() {
    guard
      let collectionView,
      let layout = collectionView.collectionViewLayout as? TiledCollectionViewLayout,
      let originalAttributes = currentLayoutAttributes,
      originalAttributes.representedElementCategory == .supplementaryView,
      let elementKind = originalAttributes.representedElementKind
    else {
      return
    }

    let preferredAttributes = preferredLayoutAttributesFitting(originalAttributes)
    guard layout.shouldInvalidateLayout(
      forPreferredLayoutAttributes: preferredAttributes,
      withOriginalAttributes: originalAttributes
    ) else {
      return
    }
       
    let context = layout.invalidationContext(
      forPreferredLayoutAttributes: preferredAttributes,
      withOriginalAttributes: originalAttributes
    )
    context.invalidateSupplementaryElements(
      ofKind: elementKind,
      at: [originalAttributes.indexPath]
    )
    layout.invalidateLayout(with: context)
  }

  private var collectionView: UICollectionView? {
    var currentView = superview

    while let view = currentView {
      if let collectionView = view as? UICollectionView {
        return collectionView
      }

      currentView = view.superview
    }

    return nil
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
      if let supplementaryView = view as? TiledSupplementaryIntrinsicContentSizeInvalidationTarget {
        supplementaryView.didInvalidateIntrinsicContentSize(in: self)
        return
      }

      currentView = view.superview
    }
  }
}
