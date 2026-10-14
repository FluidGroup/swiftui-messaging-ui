import SwiftUI
import Testing
import UIKit
@testable import ContextOverlay

/// Verifies momentum units and the measured-destination handoff contract.
@MainActor
struct ContextOverlayVelocityTests {
  @Test
  func projectsSignedMomentumIntoPathProgressPerSecond() {
    let source = CGRect(x: 20, y: 40, width: 160, height: 80)
    let destination = source.offsetBy(dx: 100, dy: 0)

    // Covering a 100-point entry path at 100 points/second is one path/second.
    #expect(projectedInitialVelocity(CGVector(dx: 100, dy: 0), from: source, to: destination) == 1)
    #expect(projectedInitialVelocity(CGVector(dx: -100, dy: 0), from: source, to: destination) == -1)
    #expect(projectedInitialVelocity(CGVector(dx: 0, dy: 200), from: source, to: destination) == 0)

    let diagonal = source.offsetBy(dx: 100, dy: 100)
    #expect(projectedInitialVelocity(CGVector(dx: 100, dy: 100), from: source, to: diagonal) == 1)
  }

  @Test
  func coincidentDestinationAndInvalidMomentumHaveFiniteZeroSeed() {
    let source = CGRect(x: 20, y: 40, width: 160, height: 80)
    let destination = source.offsetBy(dx: 100, dy: 0)
    #expect(projectedInitialVelocity(CGVector(dx: 100, dy: 0), from: source, to: source) == 0)
    #expect(projectedInitialVelocity(CGVector(dx: CGFloat.nan, dy: 0), from: source, to: destination) == 0)
    #expect(projectedInitialVelocity(CGVector(dx: CGFloat.infinity, dy: 0), from: source, to: destination) == 0)
    #expect(projectedInitialVelocity(CGVector(dx: 100, dy: 0), from: source, to: .null) == 0)
  }

  @Test
  func nonzeroHandoffWaitsForDestinationAndConsumesMomentumOnce() async throws {
    let fixture = VelocityFixture()
    let state = fixture.makeState()
    #expect(state.present("bookmark", from: fixture.source, velocity: CGVector(dx: 100, dy: 0)))
    let presentation = try #require(state.presentation)
    fixture.connect(presentation.mirror)
    await drainVelocityCallbacks()

    #expect(state.phase == .preparing)
    #expect(!state.isSourceHidden)
    #expect(presentation.handoffInitialVelocity == nil)

    let destination = presentation.sourceRect.offsetBy(dx: 100, dy: 0)
    state.registerDestinationFrame(destination, for: presentation.id)
    await drainVelocityCallbacks()
    #expect(state.isPresented)
    #expect(state.isSourceHidden)
    #expect(presentation.handoffInitialVelocity == 1)

    // Reconnection and later layout cannot restart or reseed this entry spring.
    fixture.connect(presentation.mirror)
    state.registerDestinationFrame(destination.offsetBy(dx: 100, dy: 0), for: presentation.id)
    await drainVelocityCallbacks()
    #expect(state.presentation === presentation)
    #expect(presentation.handoffInitialVelocity == 1)
    #expect(presentation.consumeInitialVelocity() == nil)
    #expect(fixture.rendering.window === fixture.window)
    state.cancel()
  }

  @Test
  func invalidOrStaleDestinationFeedbackCannotStartVelocityEntry() async throws {
    let fixture = VelocityFixture()
    let state = fixture.makeState()
    #expect(state.present("bookmark", from: fixture.source, velocity: CGVector(dx: 100, dy: 0)))
    let previous = try #require(state.presentation)
    fixture.connect(previous.mirror)
    state.registerDestinationFrame(.zero, for: previous.id)
    state.registerDestinationFrame(previous.sourceRect.offsetBy(dx: 100, dy: 0), for: UUID())
    await drainVelocityCallbacks()
    #expect(state.phase == .preparing)
    #expect(previous.handoffInitialVelocity == nil)

    state.cancel()
    #expect(state.present("another bookmark", from: fixture.source, velocity: CGVector(dx: 100, dy: 0)))
    let replacement = try #require(state.presentation)
    fixture.connect(replacement.mirror)
    state.registerDestinationFrame(previous.sourceRect.offsetBy(dx: 100, dy: 0), for: previous.id)
    await drainVelocityCallbacks()
    #expect(state.presentation === replacement)
    #expect(state.phase == .preparing)
    #expect(replacement.handoffInitialVelocity == nil)

    state.registerDestinationFrame(replacement.sourceRect.offsetBy(dx: 100, dy: 0), for: replacement.id)
    await drainVelocityCallbacks()
    #expect(state.isPresented)
    #expect(replacement.handoffInitialVelocity == 1)
    #expect(fixture.source.isAttachedToWindow)
    state.cancel()
  }
}

/// Keeps the source and coordinate space mounted throughout queued callbacks.
@MainActor
private struct VelocityFixture {
  let window: UIWindow
  let coordinate: UIView
  let container: UIView
  let rendering: UIView
  let source: ContextOverlaySource

  init() {
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    coordinate = UIView(frame: window.bounds)
    container = UIView(frame: CGRect(x: 20, y: 40, width: 160, height: 80))
    rendering = UIView(frame: container.bounds)
    source = ContextOverlaySource()
    window.addSubview(coordinate)
    window.addSubview(container)
    container.addSubview(rendering)
    source.bind(renderingView: rendering, containerView: container)
  }

  func makeState() -> ContextOverlayState<String> {
    let state = ContextOverlayState<String>(animation: .linear(duration: 0))
    state.presentationSpringDuration = 0.01
    state.registerCoordinateView(coordinate, attached: true)
    return state
  }

  func connect(_ mirror: PortalMirror) {
    mirror.portalView.frame = rendering.bounds
    window.addSubview(mirror.portalView)
    mirror.connect(in: window)
  }
}

@MainActor
private func drainVelocityCallbacks() async {
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume() }
  }
}
