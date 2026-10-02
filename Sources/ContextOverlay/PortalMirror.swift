import SwiftUI
import UIKit
import UIPortalBridge

/// Mirrors existing rendering through UIPortalBridge's UIKit wrapper.
///
/// The source remains mounted and owns its animations. The overlay owns geometry
/// and the bridge's lifetime. An unavailable bridge is an error; its transparent
/// fallback is never accepted as a live rendering.
@MainActor
final class PortalMirror {
  let sourceView: UIView
  let sourceBounds: CGRect
  let cropRect: CGRect
  let portalView: UIPortalBridge.UIPortalView
  var onStatus: ((String, Bool) -> Void)?

  /// Creates a disconnected mirror after checking the bridge's availability.
  init(sourceView: UIView, cropRect: CGRect) throws {
    let portal = UIPortalBridge.UIPortalView(frame: .zero)
    guard portal.isAvailable else {
      throw PortalError.unavailable("UIPortalBridge is unavailable on this runtime")
    }

    self.sourceView = sourceView
    sourceBounds = sourceView.bounds
    self.cropRect = cropRect
    portalView = portal
    portal.isUserInteractionEnabled = false
    // Geometry follows the outer SwiftUI proxies, independently of the source.
    portal.matchesPosition = false
    portal.matchesTransform = false
    portal.matchesAlpha = false
    portal.hidesSourceView = false
  }

  /// Binds in the same window, checks the bridge's reference, then hides the source.
  func connect(in window: UIWindow) {
    guard sourceView.window === window else {
      disconnect()
      onStatus?("Portal source detached from its window", false)
      return
    }
    portalView.sourceView = sourceView
    guard portalView.sourceView === sourceView else {
      disconnect()
      onStatus?("Portal source binding failed", false)
      return
    }
    portalView.hidesSourceView = true
    // sourceView is a stored public bridge property. Report that reference
    // honestly; actual backend binding is verified separately by runtime tests.
    let backend = portalView.subviews.first.map { NSStringFromClass(type(of: $0)) } ?? "unavailable"
    let status = "UIPortalBridge · backend=\(backend); source reference === renderingView"
    NSLog("[ContextOverlay] %@; crop=%@", status, NSCoder.string(for: cropRect))
    onStatus?(status, true)
  }

  /// Restores the original rendering before releasing the portal's source binding.
  func disconnect() {
    portalView.hidesSourceView = false
    portalView.sourceView = nil
  }

  /// Describes a missing private runtime component without changing the renderer.
  enum PortalError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
      switch self {
      case .unavailable(let description): description
      }
    }
  }
}

/// Displays one persistent portal using the original rendering dimensions.
struct PortalView: UIViewRepresentable {
  let mirror: PortalMirror

  func makeUIView(context: Context) -> Container {
    Container(mirror: mirror)
  }

  func updateUIView(_ uiView: Container, context: Context) {}

  static func dismantleUIView(_ uiView: Container, coordinator: ()) {
    uiView.mirror.disconnect()
  }

  /// Clips and positions a portal without resizing its source rendering.
  final class Container: UIView {
    let mirror: PortalMirror

    init(mirror: PortalMirror) {
      self.mirror = mirror
      super.init(frame: .zero)
      clipsToBounds = true
      isUserInteractionEnabled = false
      addSubview(mirror.portalView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
      super.layoutSubviews()
      mirror.portalView.frame = CGRect(
        x: -mirror.cropRect.minX,
        y: -mirror.cropRect.minY,
        width: mirror.sourceView.bounds.width,
        height: mirror.sourceView.bounds.height
      )
      // The bridge wraps its backend in another UIView and sizes that child
      // with autoresizing. Keep the wrapper's layout current before drawing.
      mirror.portalView.layoutIfNeeded()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if let window {
        mirror.connect(in: window)
      } else {
        mirror.disconnect()
      }
    }
  }
}

/// Supplies the overlay's coordinate space without drawing or owning a source.
struct OverlayCoordinateMarker: UIViewRepresentable {
  let onChange: (UIView, Bool) -> Void

  func makeUIView(context: Context) -> Marker {
    let marker = Marker()
    marker.isUserInteractionEnabled = false
    marker.onChange = onChange
    return marker
  }

  func updateUIView(_ uiView: Marker, context: Context) {
    uiView.onChange = onChange
  }

  static func dismantleUIView(_ uiView: Marker, coordinator: ()) {
    uiView.onChange?(uiView, false)
    uiView.onChange = nil
  }

  /// Reports attachment synchronously so owners can stop mirroring before reuse.
  final class Marker: UIView {
    var onChange: ((UIView, Bool) -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      onChange?(self, window != nil)
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      if window != nil { onChange?(self, true) }
    }
  }
}
