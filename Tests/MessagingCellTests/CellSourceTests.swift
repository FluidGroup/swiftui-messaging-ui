import Testing
import UIKit
@testable import MessagingCell

/// Verifies live UIKit attachment and coordinate contracts used by reply handoff.
@MainActor
struct CellSourceTests {
  @Test
  func swipeTranslationChangesCurrentFrameButKeepsRestingFrame() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let parent = UIView(frame: CGRect(x: 30, y: 40, width: 260, height: 500))
    let overlay = UIView(frame: CGRect(x: 40, y: 50, width: 240, height: 500))
    window.addSubview(parent)
    window.addSubview(overlay)
    let container = UIView(frame: CGRect(x: 25, y: 60, width: 160, height: 44))
    let rendering = UIView(frame: container.bounds)
    parent.addSubview(container)
    container.addSubview(rendering)
    let source = CellSource()
    source.bind(renderingView: rendering, containerView: container)

    let restingFrame = CGRect(x: 15, y: 50, width: 160, height: 44)
    #expect(source.isAttachedToWindow)
    #expect(source.frame(in: overlay) == restingFrame)
    #expect(source.restingFrame(in: overlay) == restingFrame)

    rendering.transform = CGAffineTransform(translationX: 72, y: 0)
    #expect(source.frame(in: overlay) == CGRect(x: 87, y: 50, width: 160, height: 44))
    #expect(source.restingFrame(in: overlay) == restingFrame)

    // An overlay hides the rendering before returning its transform to identity.
    rendering.transform = .identity
    #expect(source.frame(in: overlay) == restingFrame)
    #expect(source.restingFrame(in: overlay) == restingFrame)
  }

  @Test
  func refusesCoordinateConversionAcrossWindows() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let otherWindow = UIWindow(frame: window.frame)
    let container = UIView(frame: CGRect(x: 20, y: 40, width: 160, height: 44))
    let rendering = UIView(frame: container.bounds)
    let foreignOverlay = UIView(frame: otherWindow.bounds)
    window.addSubview(container)
    container.addSubview(rendering)
    otherWindow.addSubview(foreignOverlay)
    let source = CellSource()
    source.bind(renderingView: rendering, containerView: container)

    #expect(source.isAttachedToWindow)
    #expect(source.frame(in: foreignOverlay) == nil)
    #expect(source.restingFrame(in: foreignOverlay) == nil)
  }

  @Test
  func refusesFramesWhenRenderingOrContainerDetaches() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let container = UIView(frame: CGRect(x: 20, y: 40, width: 160, height: 44))
    let rendering = UIView(frame: container.bounds)
    window.addSubview(container)
    container.addSubview(rendering)
    let source = CellSource()
    source.bind(renderingView: rendering, containerView: container)

    rendering.removeFromSuperview()
    #expect(!source.isAttachedToWindow)
    #expect(source.frame(in: window) == nil)
    #expect(source.restingFrame(in: window) == nil)

    container.addSubview(rendering)
    #expect(source.isAttachedToWindow)
    container.removeFromSuperview()
    #expect(!source.isAttachedToWindow)
    #expect(source.frame(in: window) == nil)
    #expect(source.restingFrame(in: window) == nil)
  }

  @Test
  func staleUnbindDoesNotEraseReplacementBinding() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let oldContainer = UIView(frame: CGRect(x: 10, y: 20, width: 160, height: 44))
    let oldRendering = UIView(frame: oldContainer.bounds)
    let newContainer = UIView(frame: CGRect(x: 20, y: 90, width: 160, height: 44))
    let newRendering = UIView(frame: newContainer.bounds)
    window.addSubview(oldContainer)
    window.addSubview(newContainer)
    oldContainer.addSubview(oldRendering)
    newContainer.addSubview(newRendering)
    let source = CellSource()
    source.bind(renderingView: oldRendering, containerView: oldContainer)
    source.bind(renderingView: newRendering, containerView: newContainer)

    source.unbind(from: oldContainer)
    #expect(source.view === newRendering)
    #expect(source.isAttachedToWindow)
    #expect(source.frame(in: window) == CGRect(x: 20, y: 90, width: 160, height: 44))
    #expect(source.restingFrame(in: window) == CGRect(x: 20, y: 90, width: 160, height: 44))

    source.unbind(from: newContainer)
    #expect(source.view == nil)
    #expect(!source.isAttachedToWindow)
  }

  @Test
  func bindingDoesNotRetainRenderingOrContainer() {
    let source = CellSource()
    weak var weakRendering: UIView?
    weak var weakContainer: UIView?

    autoreleasepool {
      let container = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 44))
      let rendering = UIView(frame: container.bounds)
      container.addSubview(rendering)
      source.bind(renderingView: rendering, containerView: container)
      weakRendering = rendering
      weakContainer = container
      #expect(source.view === rendering)
    }

    #expect(weakRendering == nil)
    #expect(weakContainer == nil)
    #expect(source.view == nil)
    #expect(!source.isAttachedToWindow)
  }

  @Test
  func failureRequirementDoesNotRetainRemovedCellGestureOrView() {
    let parent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let parentPan = UIPanGestureRecognizer()
    parent.addGestureRecognizer(parentPan)
    weak var weakCellPan: UIPanGestureRecognizer?
    weak var weakCell: UIView?

    autoreleasepool {
      let cell = UIView(frame: CGRect(x: 20, y: 40, width: 160, height: 44))
      let cellPan = UIPanGestureRecognizer()
      parent.addSubview(cell)
      cell.addGestureRecognizer(cellPan)
      parentPan.require(toFail: cellPan)
      weakCellPan = cellPan
      weakCell = cell

      // A reusable cell may leave the hierarchy while the parent gesture lives.
      cell.removeFromSuperview()
    }

    #expect(parent.gestureRecognizers?.contains(where: { $0 === parentPan }) == true)
    #expect(weakCellPan == nil)
    #expect(weakCell == nil)
  }
}
