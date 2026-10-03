import SwiftUI
import Testing
import UIKit
@testable import ContextOverlay

/// Verifies source handoff and cleanup using real UIKit window attachment.
@MainActor
struct ContextOverlayStateTests {
  @Test
  func rejectsDetachedRendering() {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    fixture.rendering.removeFromSuperview()

    #expect(!state.present(.bookmark, from: fixture.source))
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(!state.isSourceHidden)
  }

  @Test
  func rejectsCoordinateViewInAnotherWindow() {
    let fixture = OverlayFixture()
    let foreignWindow = UIWindow(frame: fixture.window.frame)
    let foreignCoordinate = UIView(frame: foreignWindow.bounds)
    foreignWindow.addSubview(foreignCoordinate)
    let state = ContextOverlayState<BookmarkContext>(animation: .linear(duration: 0))
    state.registerCoordinateView(foreignCoordinate, attached: true)

    #expect(fixture.source.isAttachedToWindow)
    #expect(!state.present(.bookmark, from: fixture.source))
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(foreignCoordinate.window === foreignWindow)
  }

  @Test
  func genericContextWaitsForPortalConnectionAndCancelRestoresSource() async throws {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    #expect(state.present(.bookmark, from: fixture.source))
    let presentation = try #require(state.presentation)

    // Acceptance reserves this exact source but must not acknowledge hiding yet.
    #expect(presentation.context == .bookmark)
    #expect(presentation.source === fixture.source)
    #expect(state.phase == .preparing)
    #expect(!state.isPresented)
    #expect(!state.isSourceHidden)

    fixture.connect(presentation.mirror)
    #expect(presentation.mirror.portalView.sourceView === fixture.rendering)
    #expect(portalSourceView(presentation.mirror) === fixture.rendering)
    #expect(presentation.mirror.portalView.hidesSourceView)
    #expect(portalHidesSource(presentation.mirror))
    #expect(state.phase == .preparing)
    #expect(!state.isSourceHidden)

    await nextMainQueueTurn()
    #expect(state.phase == .presenting || state.phase == .active)
    #expect(state.isPresented)
    #expect(state.isSourceHidden)

    state.cancel()
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(!state.isPresented)
    #expect(!state.isDismissing)
    #expect(!state.isSourceHidden)
    #expect(presentation.mirror.portalView.sourceView == nil)
    #expect(!presentation.mirror.portalView.hidesSourceView)
    #expect(portalSourceView(presentation.mirror) == nil)
    #expect(!portalHidesSource(presentation.mirror))
    #expect(fixture.rendering.window === fixture.window)
  }

  @Test
  func detachDisconnectsSynchronouslyBeforeDeferredObservableCleanup() async throws {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    #expect(state.present(.bookmark, from: fixture.source))
    let presentation = try #require(state.presentation)
    fixture.connect(presentation.mirror)
    await nextMainQueueTurn()

    fixture.container.removeFromSuperview()
    state.sourceDidChange(fixture.source, attached: false)

    // Reuse must be safe before the next SwiftUI update drains observable state.
    #expect(!fixture.source.isAttachedToWindow)
    #expect(portalSourceView(presentation.mirror) == nil)
    #expect(!portalHidesSource(presentation.mirror))
    #expect(state.presentation === presentation)

    await nextMainQueueTurn()
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(!state.isSourceHidden)
    #expect(fixture.container.window == nil)
  }

  @Test
  func staleQueuedCallbacksCannotCancelOrAcknowledgeReplacementPresentation() async throws {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    #expect(state.present(.bookmark, from: fixture.source))
    let previous = try #require(state.presentation)
    fixture.connect(previous.mirror)
    fixture.container.removeFromSuperview()
    state.sourceDidChange(fixture.source, attached: false)
    state.cancel()

    // Reattach and select again before the old connection/cancellation callbacks.
    fixture.window.addSubview(fixture.container)
    let replacementContext = BookmarkContext(identifier: "bookmark-73", actions: ["Rename"])
    #expect(state.present(replacementContext, from: fixture.source))
    let replacement = try #require(state.presentation)
    #expect(replacement !== previous)

    await nextMainQueueTurn()
    #expect(state.presentation === replacement)
    #expect(state.presentation?.context == replacementContext)
    #expect(state.phase == .preparing)
    #expect(!state.isPresented)
    #expect(!state.isSourceHidden)
    #expect(portalSourceView(previous.mirror) == nil)
    #expect(fixture.source.isAttachedToWindow)
    state.cancel()
  }

  @Test
  func resizedRenderingInvalidatesItsCapturedPortalGeometry() async throws {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    #expect(state.present(.bookmark, from: fixture.source))
    let presentation = try #require(state.presentation)
    fixture.connect(presentation.mirror)
    await nextMainQueueTurn()

    fixture.rendering.bounds.size.width += 12
    state.sourceDidChange(fixture.source, attached: true)

    #expect(portalSourceView(presentation.mirror) == nil)
    #expect(!portalHidesSource(presentation.mirror))
    #expect(state.presentation === presentation)
    await nextMainQueueTurn()
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(fixture.rendering.bounds.size.width == 172)
  }

  @Test
  func detachedCoordinateSpaceAlsoDisconnectsSynchronously() async throws {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    #expect(state.present(.bookmark, from: fixture.source))
    let presentation = try #require(state.presentation)
    fixture.connect(presentation.mirror)
    await nextMainQueueTurn()

    fixture.coordinate.removeFromSuperview()
    state.registerCoordinateView(fixture.coordinate, attached: false)

    #expect(portalSourceView(presentation.mirror) == nil)
    #expect(!portalHidesSource(presentation.mirror))
    #expect(state.presentation === presentation)
    await nextMainQueueTurn()
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(fixture.source.isAttachedToWindow)
  }

  @Test
  func acceptsFractionalSourceCoordinatesAndTranslationWithoutResizing() throws {
    let fixture = OverlayFixture(frame: CGRect(x: 20.1, y: 40.3, width: 160.2, height: 80.7))
    let state = fixture.makeState()
    fixture.rendering.transform = CGAffineTransform(translationX: 72.37, y: 0)

    #expect(state.present(.bookmark, from: fixture.source))
    let presentation = try #require(state.presentation)
    #expect(abs(presentation.sourceRect.minX - presentation.returnRect.minX - 72.37) < 0.001)
    #expect(abs(presentation.sourceRect.width - presentation.returnRect.width) < 0.001)
    #expect(presentation.size == fixture.rendering.bounds.size)
    #expect(state.phase == .preparing)
    state.cancel()
  }

  @Test
  func rejectsScaleOrRotationSharedByRenderingAndRestingContainer() throws {
    let transforms = [
      CGAffineTransform(scaleX: 1.1, y: 1.1),
      CGAffineTransform(rotationAngle: .pi),
    ]
    for transform in transforms {
      let fixture = OverlayFixture()
      let state = fixture.makeState()
      fixture.container.transform = transform
      let currentFrame = try #require(fixture.source.frame(in: fixture.coordinate))
      let restingFrame = try #require(fixture.source.restingFrame(in: fixture.coordinate))

      // Matching rectangles alone cannot prove the Portal preserves source axes.
      #expect(abs(currentFrame.width - restingFrame.width) < 0.001)
      #expect(abs(currentFrame.height - restingFrame.height) < 0.001)
      #expect(!state.present(.bookmark, from: fixture.source))
      #expect(state.presentation == nil)
      #expect(state.phase == .idle)
      #expect(!state.isSourceHidden)
    }
  }

  @Test
  func toleratesSubpointReturnFrameRoundingButCancelsLargerMovement() async throws {
    let fixture = OverlayFixture()
    let state = fixture.makeState()
    #expect(state.present(.bookmark, from: fixture.source))
    let presentation = try #require(state.presentation)
    fixture.connect(presentation.mirror)
    await nextMainQueueTurn()

    fixture.container.center.x += 0.1
    state.sourceDidChange(fixture.source, attached: true)
    #expect(portalSourceView(presentation.mirror) === fixture.rendering)
    await nextMainQueueTurn()
    #expect(state.presentation === presentation)
    #expect(state.isSourceHidden)

    // Meaningful return-position changes must still disconnect before reuse.
    fixture.container.center.x += 1
    state.sourceDidChange(fixture.source, attached: true)
    #expect(portalSourceView(presentation.mirror) == nil)
    #expect(!portalHidesSource(presentation.mirror))
    #expect(state.presentation === presentation)
    await nextMainQueueTurn()
    #expect(state.presentation == nil)
    #expect(state.phase == .idle)
    #expect(!state.isSourceHidden)
    #expect(fixture.source.isAttachedToWindow)
  }
}

/// A caller-defined payload unrelated to messaging or list-cell identifiers.
private struct BookmarkContext: Equatable {
  let identifier: String
  let actions: [String]
  static let bookmark = BookmarkContext(identifier: "bookmark-42", actions: ["Rename", "Archive"])
}

/// Keeps the real source, coordinate space, and window alive through async checks.
@MainActor
private struct OverlayFixture {
  let window: UIWindow
  let coordinate: UIView
  let container: UIView
  let rendering: UIView
  let source: ContextOverlaySource

  init(frame: CGRect = CGRect(x: 20, y: 40, width: 160, height: 80)) {
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    coordinate = UIView(frame: window.bounds)
    container = UIView(frame: frame)
    rendering = UIView(frame: container.bounds)
    source = ContextOverlaySource()
    window.addSubview(coordinate)
    window.addSubview(container)
    container.addSubview(rendering)
    source.bind(renderingView: rendering, containerView: container)
  }

  func makeState() -> ContextOverlayState<BookmarkContext> {
    let state = ContextOverlayState<BookmarkContext>(animation: .linear(duration: 0))
    state.registerCoordinateView(coordinate, attached: true)
    return state
  }

  func connect(_ mirror: PortalMirror) {
    mirror.portalView.frame = rendering.bounds
    mirror.portalView.layoutIfNeeded()
    window.addSubview(mirror.portalView)
    mirror.connect(in: window)
  }
}

/// Drains handoff callbacks without waiting on an arbitrary elapsed duration.
@MainActor
private func nextMainQueueTurn() async {
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume() }
  }
}

/// Reads the backend only in tests: the bridge's public source is a stored value,
/// so checking it alone would not prove binding to the original rendering.
@MainActor
private func portalSourceView(_ mirror: PortalMirror) -> UIView? {
  mirror.portalView.subviews.first?.value(forKey: "sourceView") as? UIView
}

@MainActor
private func portalHidesSource(_ mirror: PortalMirror) -> Bool {
  (mirror.portalView.subviews.first?.value(forKey: "hidesSourceView") as? NSNumber)?.boolValue == true
}
