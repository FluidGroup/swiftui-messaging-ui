import SwiftUI
import SwiftUISnapDraggingModifier
import UIKit

/// Hosts one live rendering and requests reply from a velocity-aware right drag.
///
/// SnapDraggingModifier owns gesture delivery, rubber banding and cancellation
/// springs. A stationary UIKit marker describes the return slot independently
/// of the hosted rendering that the modifier translates. The package-owned pan
/// attaches to this cell's UIKit host before the first touch. Availability follows
/// the directional API's iOS 18 requirement.
@available(iOS 18.0, *)
@MainActor
public struct MessageCell<Content: View>: View {
  private let source: CellSource
  private let content: Content
  private let replyConfiguration: CellReplyConfiguration
  private let isReplyEnabled: Bool
  private let replyPhase: CellReplyPhase
  private let onReply: ((CellSource, CellReplyRelease) -> Bool)?
  private let onSourceChange: (CellSource, Bool) -> Void
  @Environment(\.isEnabled) private var isEnabled
  @State private var offset: CGSize = .zero
  @State private var bridge: CellHostingBridge

  /// Creates a cell whose rendering survives the Portal handoff and return.
  /// - Parameters:
  ///   - source: A reference belonging to this mounted cell alone.
  ///   - replyConfiguration: Distance, velocity projection and rubber banding.
  ///   - isReplyEnabled: Whether a new gesture may begin.
  ///   - replyPhase: Hold release position while preparing; reset only after hidden.
  ///   - onReply: Receives the source and physical release velocity. Return true
  ///     while entering preparing to hold the rendering for the overlay.
  ///   - onSourceChange: Synchronous attachment/layout/detach notifications.
  ///   - content: The original SwiftUI subtree; no duplicate destination is made.
  public init(
    source: CellSource,
    replyConfiguration: CellReplyConfiguration = .init(),
    isReplyEnabled: Bool = true,
    replyPhase: CellReplyPhase = .idle,
    onReply: ((CellSource, CellReplyRelease) -> Bool)? = nil,
    onSourceChange: @escaping (CellSource, Bool) -> Void = { _, _ in },
    @ViewBuilder content: () -> Content
  ) {
    self.source = source
    self.content = content()
    self.replyConfiguration = replyConfiguration
    self.isReplyEnabled = isReplyEnabled
    self.replyPhase = replyPhase
    self.onReply = onReply
    self.onSourceChange = onSourceChange
    _bridge = State(initialValue: CellHostingBridge(source: source))
  }

  public var body: some View {
    CellRendering(bridge: bridge, content: content, onSourceChange: onSourceChange)
      .modifier(SnapDraggingModifier(
        gestureMode: .directional(
          isEnabled: isEnabled && isReplyEnabled && onReply != nil && replyPhase == .idle,
          attachmentView: { bridge.rendering?.superview },
          shouldBegin: { bridge.shouldBegin($0) },
          onRecognizer: { bridge.register($0) }
        ),
        offset: $offset,
        axis: .horizontal,
        horizontalBoundary: .init(
          min: 0, max: replyConfiguration.activationDistance,
          bandLength: replyConfiguration.bandLength
        ),
        springParameter: .interpolation(mass: 1, stiffness: 195, damping: 23),
        cancelTargetOffset: .zero,
        handler: .init(onEndDraggingWithPresentation: { velocity, releasedOffset, renderedOffset, _ in
          bridge.updateDrawingTranslation(renderedOffset)
          let release = CellReplyRelease(offset: releasedOffset, velocity: velocity)
          NSLog("[MessagingCell] snap release offset=%.2f velocity=%.2f pt/s", releasedOffset.width, velocity.dx)
          if let window = source.view?.window,
            let current = source.frame(in: window), let resting = source.restingFrame(in: window) {
            NSLog("[MessagingCell] rendering translation=%.2f; resting=%@", current.minX - resting.minX, NSCoder.string(for: resting))
          }
          if bridge.ownsAttachedSource, replyPhase == .idle, isReplyEnabled, isEnabled,
            replyConfiguration.accepts(release), onReply?(source, release) == true {
            // The overlay captured the drawn position and the original physical
            // velocity. Hold that position until Portal acknowledges hiding the
            // source instead of continuing toward the gesture's newer target.
            velocity = .zero
            return renderedOffset
          }
          bridge.clearDrawingTranslation()
          return .zero
        })
      ))
      .background { CellRestingMarker(bridge: bridge) }
      .onChange(of: replyPhase) { previous, phase in
        if phase == .presented || (phase == .idle && previous != .idle) {
          var transaction = Transaction(animation: nil)
          transaction.disablesAnimations = true
          withTransaction(transaction) { offset = .zero }
          bridge.clearDrawingTranslation()
        }
      }
  }
}

/// Shares weak rendering, stationary marker and package recognizer references.
@available(iOS 18.0, *)
@MainActor
private final class CellHostingBridge {
  let source: CellSource
  weak var rendering: UIView?
  weak var marker: UIView?
  private weak var pan: UIPanGestureRecognizer?
  private weak var configuredNavigation: UINavigationController?
  private weak var configuredContentBack: UIGestureRecognizer?
  private weak var configuredScrollView: UIScrollView?
  private var didBind = false
  private var isRetired = false
  var onSourceChange: (CellSource, Bool) -> Void = { _, _ in }

  init(source: CellSource) { self.source = source }

  var ownsAttachedSource: Bool {
    !isRetired && rendering != nil && source.view === rendering && source.isAttachedToWindow
  }

  func updateDrawingTranslation(_ translation: CGSize) {
    // A queued animation frame from a dismantled host must not change a newer
    // rendering that has been bound to the same externally retained reference.
    guard !isRetired, let rendering, let marker, source.view === rendering,
      rendering.window != nil, rendering.window === marker.window else { return }
    // Depending on the hosting hierarchy, UIKit conversion can already include
    // some or all of GeometryEffect's translation. Report only its remainder;
    // adding the full offset would count that movement twice.
    let converted = rendering.convert(rendering.bounds, to: marker)
    source.setDrawingTranslation(CGSize(
      width: translation.width - (converted.minX - marker.bounds.minX),
      height: translation.height - (converted.minY - marker.bounds.minY)
    ))
  }

  func clearDrawingTranslation() {
    guard !isRetired, let rendering, source.view === rendering else { return }
    source.setDrawingTranslation(.zero)
  }

  func notifyAttachment() {
    guard !isRetired, let rendering, let marker else { return }
    // Once replaced, an old host's queued layout or detach notification cannot
    // reclaim the reference or invalidate the newer rendering's presentation.
    if didBind, let current = source.view, current !== rendering {
      isRetired = true
      return
    }
    guard let window = rendering.window, marker.window === window else {
      disconnect()
      return
    }
    if let previous = source.view, previous !== rendering {
      onSourceChange(source, false)
    }
    source.bind(renderingView: rendering, containerView: marker)
    didBind = true
    configureGesturePriority()
    onSourceChange(source, source.isAttachedToWindow)
  }

  func detachRendering(_ view: UIView) {
    guard rendering === view else { return }
    isRetired = true
    disconnect()
    rendering = nil
  }

  func detachMarker(_ view: UIView) {
    guard marker === view else { return }
    isRetired = true
    disconnect()
    marker = nil
  }

  private func disconnect() {
    guard let rendering, source.view === rendering else { return }
    onSourceChange(source, false)
    if let marker { source.unbind(from: marker) }
  }

  func register(_ gesture: UIPanGestureRecognizer) {
    if pan !== gesture {
      pan = gesture
      configuredNavigation = nil
      configuredContentBack = nil
      configuredScrollView = nil
    }
    configureGesturePriority()
  }

  func shouldBegin(_ admission: GestureModeDirectional.Admission) -> Bool {
    guard ownsAttachedSource, admission.translation.x > 0 else { return false }
    // Physical edge back remains available even for a row touching the edge.
    if let marker, let window = marker.window, navigationController != nil {
      let start = admission.gestureRecognizer.location(in: window)
      let translation = admission.gestureRecognizer.translation(in: window)
      if start.x - translation.x < window.safeAreaInsets.left + 20 { return false }
    }
    return true
  }

  private var navigationController: UINavigationController? {
    var responder: UIResponder? = marker ?? rendering
    while let current = responder {
      if let navigation = current as? UINavigationController { return navigation }
      if let controller = current as? UIViewController, let navigation = controller.navigationController { return navigation }
      responder = current.next
    }
    return nil
  }

  private func configureGesturePriority() {
    guard let pan else { return }
    var ancestor = marker?.superview ?? rendering?.superview
    while let view = ancestor {
      if let scrollView = view as? UIScrollView {
        if configuredScrollView !== scrollView {
          scrollView.panGestureRecognizer.require(toFail: pan)
          configuredScrollView = scrollView
        }
        break
      }
      ancestor = view.superview
    }
    if let navigation = navigationController {
      if configuredNavigation !== navigation {
        if let edgeBack = navigation.interactivePopGestureRecognizer { pan.require(toFail: edgeBack) }
        configuredNavigation = navigation
      }
      // Full-content back may become available after this cell first attaches.
      // Track the recognizer separately so an earlier nil is not cached forever.
      if #available(iOS 26.0, *), let contentBack = navigation.interactiveContentPopGestureRecognizer,
        configuredContentBack !== contentBack {
        contentBack.require(toFail: pan)
        configuredContentBack = contentBack
      }
    }
  }
}

/// Preserves a single UIHostingConfiguration rendering and the caller environment.
@available(iOS 18.0, *)
private struct CellRendering<Content: View>: UIViewRepresentable {
  let bridge: CellHostingBridge
  let content: Content
  let onSourceChange: (CellSource, Bool) -> Void

  func makeUIView(context: Context) -> Host<Content> {
    bridge.onSourceChange = onSourceChange
    return Host(bridge: bridge, root: CellHostedContent(content: content, environment: context.environment))
  }

  func updateUIView(_ uiView: Host<Content>, context: Context) {
    bridge.onSourceChange = onSourceChange
    uiView.contentView.configuration = UIHostingConfiguration {
      CellHostedContent(content: content, environment: context.environment)
    }.margins(.all, 0).minSize(width: 0, height: 0)
    uiView.invalidateIntrinsicContentSize()
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: Host<Content>, context: Context) -> CGSize? {
    let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? UIView.layoutFittingExpandedSize.width
    return uiView.contentView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
  }

  static func dismantleUIView(_ uiView: Host<Content>, coordinator: ()) {
    uiView.bridge.detachRendering(uiView.contentView)
  }

  /// Owns the live content view while SwiftUI translates this host's subtree.
  final class Host<C: View>: UIView {
    let contentView: any UIView & UIContentView
    let bridge: CellHostingBridge

    init(bridge: CellHostingBridge, root: CellHostedContent<C>) {
      self.bridge = bridge
      contentView = UIHostingConfiguration { root }.margins(.all, 0).minSize(width: 0, height: 0).makeContentView()
      super.init(frame: .zero)
      backgroundColor = .clear
      contentView.backgroundColor = .clear
      contentView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(contentView)
      NSLayoutConstraint.activate([
        contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        contentView.topAnchor.constraint(equalTo: topAnchor),
        contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
      bridge.rendering = contentView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var safeAreaInsets: UIEdgeInsets { .zero }
    override var intrinsicContentSize: CGSize { contentView.intrinsicContentSize }
    override func didMoveToWindow() { super.didMoveToWindow(); bridge.notifyAttachment() }
    override func layoutSubviews() { super.layoutSubviews(); bridge.notifyAttachment() }
  }
}

/// Keeps the original footprint outside the modifier's animated translation.
@available(iOS 18.0, *)
private struct CellRestingMarker: UIViewRepresentable {
  let bridge: CellHostingBridge

  func makeUIView(context: Context) -> Marker {
    let marker = Marker()
    marker.isUserInteractionEnabled = false
    marker.bridge = bridge
    bridge.marker = marker
    bridge.notifyAttachment()
    return marker
  }

  func updateUIView(_ uiView: Marker, context: Context) {}
  static func dismantleUIView(_ uiView: Marker, coordinator: ()) { uiView.bridge?.detachMarker(uiView) }

  /// Reports the fixed layout independently of the translated rendering view.
  final class Marker: UIView {
    weak var bridge: CellHostingBridge?
    override func didMoveToWindow() { super.didMoveToWindow(); bridge?.notifyAttachment() }
    override func layoutSubviews() { super.layoutSubviews(); bridge?.notifyAttachment() }
  }
}

/// Keeps the root type stable as configuration values and environments update.
private struct CellHostedContent<Content: View>: View {
  let content: Content
  let environment: EnvironmentValues
  var body: some View { content.environment(\.self, environment) }
}
