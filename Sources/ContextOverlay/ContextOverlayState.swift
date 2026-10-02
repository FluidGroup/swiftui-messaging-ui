import Observation
import SwiftUI
import UIKit

/// The lifecycle of a live rendering in a contextual overlay.
public enum ContextOverlayPhase: Equatable, Sendable {
  /// No source is selected.
  case idle
  /// The overlay is attaching its mirror; the source stays at its release frame.
  case preparing
  /// The source is hidden and the mirror is moving toward its destination.
  case presenting
  /// The destination is active and may expose contextual actions.
  case active
  /// The mirror is returning to the source's resting frame.
  case dismissing
}

/// Carries caller-defined context and one existing rendering through an overlay.
///
/// The context can be any value. The destination uses ``sourcePlaceholder``;
/// the overlay owns the single live mirror rather than drawing the content again.
@MainActor
public final class ContextOverlayPresentation<Context>: Identifiable {
  public let id = UUID()
  /// The value supplied by the caller when opening the overlay.
  public let context: Context
  /// The source reference whose owner must stay mounted until return completes.
  public let source: ContextOverlaySource
  /// The original rendering dimensions, preserved throughout presentation.
  public var size: CGSize { mirror.cropRect.size }
  /// Reserves the destination for the live rendering in the caller's layout.
  ///
  /// Insert exactly one placeholder inside ``ContextOverlay``. It can be placed
  /// in a stack or ScrollView, surrounded by arbitrary controls and padding.
  /// Matching transfers position and preserves the original dimensions. Masks,
  /// transforms and clipping around the placeholder do not style the Portal.
  public var sourcePlaceholder: some View {
    ContextOverlayDestination(id: id, size: size)
  }

  let sourceRect: CGRect
  let returnRect: CGRect
  let mirror: PortalMirror
  let releaseVelocity: CGVector
  var destinationRect: CGRect?
  var isMirrorConnected = false
  private(set) var handoffInitialVelocity: Double?

  init(
    context: Context, source: ContextOverlaySource, sourceRect: CGRect,
    returnRect: CGRect, mirror: PortalMirror, releaseVelocity: CGVector
  ) {
    self.context = context
    self.source = source
    self.sourceRect = sourceRect
    self.returnRect = returnRect
    self.mirror = mirror
    self.releaseVelocity = releaseVelocity
  }

  /// Consumes release momentum once, after the destination has a measured slot.
  func consumeInitialVelocity() -> Double? {
    guard handoffInitialVelocity == nil else { return nil }
    let velocity: Double
    if releaseVelocity == .zero { velocity = 0 }
    else {
      guard let destinationRect else { return nil }
      velocity = projectedInitialVelocity(releaseVelocity, from: sourceRect, to: destinationRect)
    }
    handoffInitialVelocity = velocity
    return velocity
  }
}

/// Owns one message-independent overlay presentation and its UIKit handoff.
///
/// Keep this object in the presenting screen's state. Source owners report
/// attachment/layout changes through ``sourceDidChange(_:attached:)``. The
/// experimental renderer uses `_UIPortalView`; unsupported runtimes fail without
/// substituting a snapshot or a separately rendered SwiftUI view.
@MainActor
@Observable
public final class ContextOverlayState<Context> {
  /// The selected context and source, or nil after cleanup.
  public private(set) var presentation: ContextOverlayPresentation<Context>?
  /// The current lifecycle; presentation flags are derived from this value.
  public private(set) var phase = ContextOverlayPhase.idle
  /// A diagnostic result for development and runtime capability checking.
  public private(set) var status = "No context overlay is presented."
  /// The animation used for the next presentation or return.
  public var animation: Animation
  /// The spring duration in seconds for an entry carrying release momentum.
  ///
  /// Zero-velocity entry and return keep using ``animation``. A velocity handoff
  /// uses an interpolating spring with this duration and a bounce of 0.18. Set
  /// this alongside `animation` when changing presentation speed.
  public var presentationSpringDuration: TimeInterval = 0.45 {
    didSet { precondition(presentationSpringDuration > 0 && presentationSpringDuration.isFinite) }
  }
  @ObservationIgnored private weak var coordinateView: UIView?

  /// Whether the destination is visible, including its entry animation.
  public var isPresented: Bool { phase == .presenting || phase == .active }
  /// Whether the return animation is in progress.
  public var isDismissing: Bool { phase == .dismissing }
  /// Whether Portal has acknowledged hiding the source rendering.
  ///
  /// A swipe owner may reset its hidden source translation only after this
  /// becomes true. Hiding remains in effect throughout the return animation.
  public var isSourceHidden: Bool { phase != .idle && phase != .preparing }

  /// Creates presentation state without selecting or retaining a source.
  public init(animation: Animation = .spring(response: 0.45, dampingFraction: 0.82)) {
    self.animation = animation
  }

  /// Opens a live overlay using the source's current and resting coordinates.
  /// - Parameters:
  ///   - context: A caller-defined value for destination content and actions.
  ///   - source: The mounted source whose rendering remains alive during return.
  ///   - velocity: Release velocity in points per second in the overlay's axes.
  ///     The spring receives its scalar projection along source-to-destination
  ///     displacement. Perpendicular momentum is not preserved as a second path.
  /// - Returns: True if the handoff was accepted; false if another overlay is
  ///   present, geometry is unavailable, or the Portal renderer is unavailable.
  @discardableResult
  public func present(_ context: Context, from source: ContextOverlaySource, velocity: CGVector = .zero) -> Bool {
    guard presentation == nil, let coordinateView,
      let rendering = source.view,
      let sourceRect = source.frame(in: coordinateView),
      let returnRect = source.restingFrame(in: coordinateView),
      rendering.bounds.origin == .zero,
      rendering.bounds.width > 0, rendering.bounds.height > 0,
      // Converting a translated source can introduce tiny rounding differences.
      abs(sourceRect.width - returnRect.width) < 0.5,
      abs(sourceRect.height - returnRect.height) < 0.5
    else { return false }

    guard supportsSourceGeometry(rendering, in: coordinateView) else {
      status = "Context overlay supports source translation without scale or rotation."
      return false
    }

    do {
      let mirror = try PortalMirror(sourceView: rendering, cropRect: rendering.bounds)
      let releaseVelocity = velocity.dx.isFinite && velocity.dy.isFinite ? velocity : .zero
      let next = ContextOverlayPresentation(
        context: context, source: source, sourceRect: sourceRect, returnRect: returnRect,
        mirror: mirror, releaseVelocity: releaseVelocity
      )
      mirror.onStatus = { [weak self, weak next] status, connected in
        // UIKit attachment may occur during a SwiftUI update. Mutate observable
        // presentation state only after that update has completed.
        DispatchQueue.main.async {
          guard let self, let next, self.presentation === next else { return }
          self.status = status
          if connected {
            next.isMirrorConnected = true
            self.animatePresentationIfReady(next)
          } else {
            self.cancel()
            self.status = status
          }
        }
      }
      presentation = next
      phase = .preparing
      status = "Attaching the live rendering."
      return true
    } catch {
      status = error.localizedDescription
      return false
    }
  }

  /// Animates back to the captured resting frame, then restores the source.
  public func dismiss() {
    guard let current = presentation, phase != .dismissing else { return }
    if phase == .preparing { cancel(); return }
    withAnimation(animation, completionCriteria: .removed) {
      phase = .dismissing
    } completion: { [weak self, weak current] in
      guard let self, let current, self.presentation === current else { return }
      self.cancel()
    }
  }

  /// Immediately disconnects the mirror and restores the original rendering.
  ///
  /// Call when the presenting screen disappears or an action requires immediate
  /// cleanup. Source lifecycle callbacks should use ``sourceDidChange(_:attached:)``.
  public func cancel() {
    presentation?.mirror.disconnect()
    presentation = nil
    phase = .idle
    status = "Portal released; original rendering restored."
  }

  /// Validates the selected source when its owner attaches, lays out, or detaches.
  ///
  /// Detach or changed identity/geometry disconnects Portal synchronously before
  /// reuse. Observable cleanup is deferred beyond the UIKit layout callback.
  public func sourceDidChange(_ source: ContextOverlaySource, attached: Bool) {
    guard presentation?.source === source else { return }
    if attached { validateSourceGeometry() }
    else { invalidateSource() }
  }

  func registerCoordinateView(_ view: UIView, attached: Bool) {
    if attached {
      coordinateView = view
      validateSourceGeometry()
    } else if coordinateView === view {
      coordinateView = nil
      invalidateSource()
    }
  }

  /// Accepts only the preparing presentation's destination measurement.
  func registerDestinationFrame(_ frame: CGRect, for presentationID: UUID) {
    guard frame.origin.x.isFinite, frame.origin.y.isFinite,
      frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0
    else { return }
    // Geometry callbacks can run during layout. Defer observable phase changes,
    // and check identity again so an old placeholder cannot seed a new handoff.
    DispatchQueue.main.async { [weak self] in
      guard let self, let current = self.presentation,
        current.id == presentationID, self.phase == .preparing else { return }
      current.destinationRect = frame
      self.animatePresentationIfReady(current)
    }
  }

  private func animatePresentationIfReady(_ current: ContextOverlayPresentation<Context>) {
    guard presentation === current, phase == .preparing, current.isMirrorConnected,
      let initialVelocity = current.consumeInitialVelocity() else { return }
    // Nonzero momentum waits for destination geometry; a tap keeps its original
    // animation and does not depend on a geometry callback to leave preparing.
    let entryAnimation = initialVelocity == 0 ? animation : Animation.interpolatingSpring(
      duration: presentationSpringDuration, bounce: 0.18, initialVelocity: initialVelocity
    )
    NSLog("[ContextOverlay] entry projectedVelocity=%g/s duration=%g", initialVelocity, presentationSpringDuration)
    withAnimation(entryAnimation, completionCriteria: .logicallyComplete) {
      phase = .presenting
    } completion: { [weak self, weak current] in
      guard let self, let current, self.presentation === current, self.phase == .presenting else { return }
      self.phase = .active
    }
  }

  private func validateSourceGeometry() {
    guard let current = presentation, let coordinateView else { return }
    let source = current.source
    if !source.isAttachedToWindow || source.view !== current.mirror.sourceView
      || source.view?.bounds != current.mirror.sourceBounds
      || !supportsSourceGeometry(current.mirror.sourceView, in: coordinateView)
      || !framesMatch(source.restingFrame(in: coordinateView), current.returnRect) {
      invalidateSource()
    }
  }

  /// The Portal follows position while source dimensions and axes stay intact.
  private func supportsSourceGeometry(_ view: UIView, in coordinateView: UIView) -> Bool {
    let bounds = view.bounds
    let origin = view.convert(bounds.origin, to: coordinateView)
    let x = view.convert(CGPoint(x: bounds.maxX, y: bounds.minY), to: coordinateView)
    let y = view.convert(CGPoint(x: bounds.minX, y: bounds.maxY), to: coordinateView)
    return abs(x.x - origin.x - bounds.width) < 0.5 && abs(x.y - origin.y) < 0.5
      && abs(y.y - origin.y - bounds.height) < 0.5 && abs(y.x - origin.x) < 0.5
  }

  /// Allows conversion rounding while still cancelling meaningful movement.
  private func framesMatch(_ frame: CGRect?, _ captured: CGRect) -> Bool {
    guard let frame else { return false }
    return abs(frame.minX - captured.minX) < 0.5 && abs(frame.minY - captured.minY) < 0.5
      && abs(frame.width - captured.width) < 0.5 && abs(frame.height - captured.height) < 0.5
  }

  private func invalidateSource() {
    presentation?.mirror.disconnect()
    guard let current = presentation else { return }
    DispatchQueue.main.async { [weak self, weak current] in
      guard let self, let current, self.presentation === current else { return }
      self.cancel()
      self.status = "Portal cancelled because its source or geometry changed."
    }
  }
}

/// Converts point velocity into signed progress per second along the entry path.
///
/// This scalar preserves momentum parallel to matched geometry's displacement;
/// it cannot reproduce independent horizontal and vertical motion. Invalid or
/// negligible displacement yields zero rather than an unbounded spring seed.
func projectedInitialVelocity(_ velocity: CGVector, from source: CGRect, to destination: CGRect) -> Double {
  let dx = destination.midX - source.midX
  let dy = destination.midY - source.midY
  let distanceSquared = dx * dx + dy * dy
  guard velocity.dx.isFinite, velocity.dy.isFinite,
    dx.isFinite, dy.isFinite, distanceSquared.isFinite, distanceSquared > 0.25
  else { return 0 }
  let projected = (velocity.dx * dx + velocity.dy * dy) / distanceSquared
  return projected.isFinite ? Double(projected) : 0
}
