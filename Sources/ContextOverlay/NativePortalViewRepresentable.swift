import SwiftUI
import UIKit

/// Adapts a native portal's layout and binding lifetime to a SwiftUI destination.
///
/// The destination keeps the source's untransformed dimensions. Matched geometry
/// belongs to SwiftUI; native forwarding preserves the source's interactive views.
struct NativePortalViewRepresentable: UIViewRepresentable {

  let sourceView: UIView
  let configuration: PortalDestination.Configuration

  func makeUIView(context: Context) -> NativePortalView {
    guard let portal = NativePortalView(sourceView: nil) else {
      preconditionFailure("Native portal is unavailable on this runtime")
    }
    configure(portal)
    return portal
  }

  func updateUIView(_ uiView: NativePortalView, context: Context) {
    configure(uiView)
  }

  /// Applies live options and restores the previous source before rebinding.
  func configure(_ portal: NativePortalView) {
    let sourceChanged = portal.sourceView !== sourceView
    if sourceChanged {
      portal.disconnect()
    }
    portal.matchesAlpha = configuration.matchesAlpha
    portal.matchesTransform = configuration.matchesTransform
    portal.matchesPosition = configuration.matchesPosition
    portal.allowsHitTesting = configuration.allowsHitTesting
    portal.forwardsClientHitTestingToSourceView = configuration.forwardsClientHitTestingToSourceView
    if sourceChanged {
      portal.sourceView = sourceView
    }
    // Hiding must be applied after binding, and also on same-source updates.
    portal.hidesSourceView = configuration.hidesSourceView
    portal.invalidateIntrinsicContentSize()
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: NativePortalView,
    context: Context
  ) -> CGSize? {
    let size = uiView.intrinsicContentSize
    return size.width > 0 && size.height > 0 ? size : nil
  }

  static func dismantleUIView(_ uiView: NativePortalView, coordinator: ()) {
    uiView.disconnect()
  }
}
