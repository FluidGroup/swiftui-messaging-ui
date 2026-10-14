import Testing
import UIKit
@testable import ContextOverlay

/// Verifies visual offsets that UIKit geometry does not report during handoff.
@MainActor
struct ContextOverlaySourceTests {
  @Test
  func additionalDrawingTranslationChangesCurrentFrameWithoutMovingReturnSlot() {
    let fixture = DrawingTranslationFixture()
    let restingFrame = CGRect(x: 15, y: 50, width: 160, height: 44)
    #expect(fixture.source.isAttachedToWindow)
    #expect(fixture.source.frame(in: fixture.coordinate) == restingFrame)

    fixture.source.setDrawingTranslation(CGSize(width: 40, height: 12))

    #expect(fixture.source.frame(in: fixture.coordinate) == CGRect(x: 55, y: 62, width: 160, height: 44))
    #expect(fixture.source.restingFrame(in: fixture.coordinate) == restingFrame)
    // The reported drawing offset represents a SwiftUI effect, not a UIView move.
    #expect(fixture.rendering.convert(fixture.rendering.bounds, to: fixture.coordinate) == restingFrame)

    fixture.rendering.transform = CGAffineTransform(translationX: 18, y: -5)
    #expect(fixture.source.frame(in: fixture.coordinate) == CGRect(x: 73, y: 57, width: 160, height: 44))
    #expect(fixture.source.restingFrame(in: fixture.coordinate) == restingFrame)
  }

  @Test
  func layoutRebindingTheSameViewsKeepsTheirDrawingTranslation() {
    let fixture = DrawingTranslationFixture()
    fixture.source.setDrawingTranslation(CGSize(width: 40, height: 12))

    fixture.source.bind(renderingView: fixture.rendering, containerView: fixture.container)
    fixture.source.bind(renderingView: fixture.rendering, containerView: fixture.container)

    #expect(fixture.source.view === fixture.rendering)
    #expect(fixture.source.frame(in: fixture.coordinate) == CGRect(x: 55, y: 62, width: 160, height: 44))
    #expect(fixture.source.restingFrame(in: fixture.coordinate) == CGRect(x: 15, y: 50, width: 160, height: 44))
  }

  @Test
  func replacingTheRenderingViewDoesNotInheritAnEarlierDrawingTranslation() {
    let fixture = DrawingTranslationFixture()
    fixture.source.setDrawingTranslation(CGSize(width: 40, height: 12))
    let replacement = UIView(frame: fixture.container.bounds)
    fixture.container.addSubview(replacement)

    fixture.source.bind(renderingView: replacement, containerView: fixture.container)

    #expect(fixture.source.view === replacement)
    #expect(fixture.source.isAttachedToWindow)
    #expect(fixture.source.frame(in: fixture.coordinate) == CGRect(x: 15, y: 50, width: 160, height: 44))
    #expect(fixture.source.restingFrame(in: fixture.coordinate) == CGRect(x: 15, y: 50, width: 160, height: 44))
  }

  @Test
  func replacingTheContainerResetsTranslationAndIgnoresItsStaleTeardown() {
    let fixture = DrawingTranslationFixture()
    fixture.source.setDrawingTranslation(CGSize(width: 40, height: 12))
    let replacementContainer = UIView(frame: CGRect(x: 50, y: 110, width: 160, height: 44))
    fixture.parent.addSubview(replacementContainer)
    replacementContainer.addSubview(fixture.rendering)

    fixture.source.bind(renderingView: fixture.rendering, containerView: replacementContainer)
    let replacementFrame = CGRect(x: 40, y: 100, width: 160, height: 44)
    #expect(fixture.source.frame(in: fixture.coordinate) == replacementFrame)
    #expect(fixture.source.restingFrame(in: fixture.coordinate) == replacementFrame)

    fixture.source.setDrawingTranslation(CGSize(width: 12, height: 5))
    fixture.source.unbind(from: fixture.container)

    #expect(fixture.source.view === fixture.rendering)
    #expect(fixture.source.isAttachedToWindow)
    #expect(fixture.source.frame(in: fixture.coordinate) == CGRect(x: 52, y: 105, width: 160, height: 44))
    #expect(fixture.source.restingFrame(in: fixture.coordinate) == replacementFrame)

    fixture.source.unbind(from: replacementContainer)
    #expect(fixture.source.view == nil)
    #expect(fixture.source.frame(in: fixture.coordinate) == nil)
    fixture.source.bind(renderingView: fixture.rendering, containerView: replacementContainer)
    #expect(fixture.source.frame(in: fixture.coordinate) == replacementFrame)
  }
}

/// Keeps two real coordinate branches attached to one window through each check.
@MainActor
private struct DrawingTranslationFixture {
  let window: UIWindow
  let parent: UIView
  let coordinate: UIView
  let container: UIView
  let rendering: UIView
  let source: ContextOverlaySource

  init() {
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    parent = UIView(frame: CGRect(x: 30, y: 40, width: 260, height: 500))
    coordinate = UIView(frame: CGRect(x: 40, y: 50, width: 240, height: 500))
    container = UIView(frame: CGRect(x: 25, y: 60, width: 160, height: 44))
    rendering = UIView(frame: container.bounds)
    source = ContextOverlaySource()
    window.addSubview(parent)
    window.addSubview(coordinate)
    parent.addSubview(container)
    container.addSubview(rendering)
    source.bind(renderingView: rendering, containerView: container)
  }
}
