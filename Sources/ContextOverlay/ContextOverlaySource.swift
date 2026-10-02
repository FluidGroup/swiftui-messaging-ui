import UIKit

/// A weak reference to existing UIKit rendering that can move into an overlay.
///
/// Keep this reference in the source's SwiftUI state or UIKit owner. The owner
/// retains the rendering and its stationary container; this reference retains
/// neither. The rendering may be translated during a gesture while the container
/// continues to describe the location to which the overlay should return.
@MainActor
public final class ContextOverlaySource {
  private weak var renderingView: UIView?
  private weak var containerView: UIView?
  private var drawingTranslation: CGSize = .zero

  /// Creates an initially unbound rendering reference.
  public init() {}

  /// The original view that draws the content, including its ongoing animations.
  ///
  /// This is the source's rendering view, rather than a snapshot, geometry marker,
  /// or a second instance of its content.
  public var view: UIView? { renderingView }

  /// Whether the rendering and its stationary container share an attached window.
  public var isAttachedToWindow: Bool {
    guard let window = renderingView?.window else { return false }
    return containerView?.window === window
  }

  /// Returns the current drawing frame, including the rendering's transform.
  /// - Parameter coordinateView: A view or window in the source's window.
  /// - Returns: The converted frame, or `nil` while detached or across windows.
  public func frame(in coordinateView: UIView) -> CGRect? {
    guard isAttachedToWindow, let renderingView,
      (coordinateView as? UIWindow ?? coordinateView.window) === renderingView.window else { return nil }
    let frame = renderingView.convert(renderingView.bounds, to: coordinateView)
    let origin = renderingView.convert(CGPoint.zero, to: coordinateView)
    let translated = renderingView.convert(
      CGPoint(x: drawingTranslation.width, y: drawingTranslation.height), to: coordinateView
    )
    return frame.offsetBy(dx: translated.x - origin.x, dy: translated.y - origin.y)
  }

  /// Returns the stationary frame to use when returning from an overlay.
  ///
  /// Capture this frame together with ``frame(in:)`` before hiding the rendering.
  /// A swipe implementation should transform the rendering alone and keep its
  /// container stationary so this frame continues to describe the original slot.
  /// - Parameter coordinateView: A view or window in the source's window.
  /// - Returns: The converted frame, or `nil` while detached or across windows.
  public func restingFrame(in coordinateView: UIView) -> CGRect? {
    guard isAttachedToWindow, let containerView,
      (coordinateView as? UIWindow ?? coordinateView.window) === containerView.window else { return nil }
    return containerView.convert(containerView.bounds, to: coordinateView)
  }

  /// Connects the rendering and stationary container owned by a UIKit component.
  ///
  /// Custom owners can supply an existing rendering without a SwiftUI source
  /// wrapper. Before replacing either view, notify the overlay about the source
  /// change so it can disconnect its mirror before reuse or reconfiguration.
  /// - Parameters:
  ///   - renderingView: The existing view whose live rendering should be mirrored.
  ///   - containerView: The stationary view describing the rendering's return slot.
  public func bind(renderingView: UIView, containerView: UIView) {
    if self.renderingView !== renderingView || self.containerView !== containerView {
      drawingTranslation = .zero
    }
    self.renderingView = renderingView
    self.containerView = containerView
  }

  /// Reports an additional visual translation not represented by UIKit geometry.
  ///
  /// SwiftUI GeometryEffect can translate a UIKit-backed drawing without changing
  /// its UIView frame. Its owner reports the rendered offset, rather than the
  /// animation's target, before opening the overlay. UIKit transforms themselves
  /// are already included by ``frame(in:)`` and must not be reported again here.
  /// - Parameter translation: The displayed offset in the rendering's local axes.
  public func setDrawingTranslation(_ translation: CGSize) {
    precondition(translation.width.isFinite && translation.height.isFinite)
    drawingTranslation = translation
  }

  /// Removes a binding only when it still belongs to the supplied container.
  ///
  /// Notify the overlay about detachment before calling this method. An older
  /// container's teardown cannot remove a newer binding to the same reference.
  /// - Parameter containerView: The container releasing its rendering binding.
  public func unbind(from containerView: UIView) {
    guard self.containerView === containerView else { return }
    renderingView = nil
    self.containerView = nil
    drawingTranslation = .zero
  }
}
