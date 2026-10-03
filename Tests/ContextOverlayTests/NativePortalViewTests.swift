import Testing
import UIKit
@testable import ContextOverlay

/// Verifies native portal hit targets while source and destination occupy separate window positions.
@MainActor
struct NativePortalViewTests {
  @Test
  func disconnectedPortalDoesNotInterceptItsBackground() throws {
    let fixture = try PortalHitTestingFixture()
    fixture.portal.sourceView = nil

    #expect(fixture.portal.hitTest(fixture.buttonPoint, with: nil) == nil)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)
  }

  @Test
  func disabledPortalHitTestingPassesThroughToItsBackground() throws {
    let fixture = try PortalHitTestingFixture()
    fixture.portal.allowsHitTesting = false

    #expect(!fixture.portal.allowsHitTesting)
    #expect(fixture.portal.hitTest(fixture.buttonPoint, with: nil) == nil)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)
  }

  @Test
  func forwardedHitReturnsTheOriginalControlAtTheDestinationPosition() throws {
    let fixture = try PortalHitTestingFixture()

    // Converting through the source's position would land outside its button.
    let windowPoint = fixture.portal.convert(fixture.buttonPoint, to: fixture.window)
    #expect(!fixture.source.bounds.contains(fixture.source.convert(windowPoint, from: fixture.window)))
    #expect(fixture.portal.hitTest(fixture.buttonPoint, with: nil) === fixture.button)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.button)
  }

  @Test
  func transformedDestinationKeepsHitsInTheMirroredContentCoordinates() throws {
    let fixture = try PortalHitTestingFixture()
    fixture.portal.transform = CGAffineTransform(translationX: 15, y: -10)
      .scaledBy(x: 1.4, y: 0.8)

    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.button)
  }

  @Test
  func sourceBoundsOriginOffsetsItsMirroredHitRegion() throws {
    let fixture = try PortalHitTestingFixture()
    fixture.source.bounds.origin = CGPoint(x: 8, y: 12)
    let mirroredPoint = CGPoint(
      x: fixture.buttonPoint.x - fixture.source.bounds.minX,
      y: fixture.buttonPoint.y - fixture.source.bounds.minY
    )

    #expect(fixture.destinationHit(at: mirroredPoint) === fixture.button)
  }

  @Test
  func sourceEmptySpacePassesThroughWithoutReturningThePortalWrapper() throws {
    let fixture = try PortalHitTestingFixture()
    let emptyPoint = CGPoint(x: 140, y: 65)
    #expect(fixture.source.hitTest(emptyPoint, with: nil) == nil)

    #expect(fixture.portal.hitTest(emptyPoint, with: nil) == nil)
    #expect(fixture.destinationHit(at: emptyPoint) === fixture.background)
  }

  @Test
  func UIKitInteractionGatesStillDisableForwardedHits() throws {
    let fixture = try PortalHitTestingFixture()
    fixture.portal.isUserInteractionEnabled = false
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)

    fixture.portal.isUserInteractionEnabled = true
    fixture.portal.isHidden = true
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)

    fixture.portal.isHidden = false
    fixture.portal.alpha = 0
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)
  }

  @Test
  func replacingTheSourceUpdatesTheForwardedControlAndKeepsFlags() throws {
    let fixture = try PortalHitTestingFixture()
    let replacement = PortalPassthroughSourceView(frame: fixture.source.frame)
    let replacementButton = UIButton(frame: fixture.button.frame)
    replacement.addSubview(replacementButton)
    fixture.root.addSubview(replacement)
    fixture.root.bringSubviewToFront(fixture.portal)

    fixture.portal.sourceView = replacement

    #expect(fixture.portal.sourceView === replacement)
    #expect(fixture.portal.allowsHitTesting)
    #expect(fixture.portal.forwardsClientHitTestingToSourceView)
    #expect(fixture.portal.hidesSourceView)
    #expect(!fixture.portal.matchesAlpha)
    #expect(!fixture.portal.matchesPosition)
    #expect(!fixture.portal.matchesTransform)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === replacementButton)
  }

  @Test
  func nativeFlagsRemainReadableAfterChangingTheSource() throws {
    let fixture = try PortalHitTestingFixture()
    fixture.portal.hidesSourceView = false
    fixture.portal.matchesAlpha = true
    fixture.portal.matchesPosition = true
    fixture.portal.matchesTransform = true
    fixture.portal.allowsHitTesting = false
    fixture.portal.forwardsClientHitTestingToSourceView = false
    fixture.portal.sourceView = nil

    #expect(!fixture.portal.hidesSourceView)
    #expect(fixture.portal.matchesAlpha)
    #expect(fixture.portal.matchesPosition)
    #expect(fixture.portal.matchesTransform)
    #expect(!fixture.portal.allowsHitTesting)
    #expect(!fixture.portal.forwardsClientHitTestingToSourceView)
  }

  @Test
  func intrinsicSizeUsesSourceBoundsInsteadOfItsTransformedFrame() throws {
    let source = UIView(frame: CGRect(x: 20, y: 40, width: 160, height: 80))
    source.bounds.origin = CGPoint(x: 8, y: 12)
    source.transform = CGAffineTransform(scaleX: 2, y: 1.5)
    let portal = try #require(NativePortalView(sourceView: source))

    #expect(source.frame.size != source.bounds.size)
    #expect(portal.intrinsicContentSize == source.bounds.size)

    let replacement = UIView(frame: CGRect(x: 0, y: 0, width: 90, height: 30))
    portal.sourceView = replacement
    #expect(portal.intrinsicContentSize == replacement.bounds.size)
  }

  @Test
  func liveConfigurationChangesHitTestingWithoutReplacingTheSource() throws {
    let fixture = try PortalHitTestingFixture()
    var configuration = PortalDestination.Configuration()
    configuration.allowsHitTesting = false

    NativePortalViewRepresentable(sourceView: fixture.source, configuration: configuration)
      .configure(fixture.portal)

    #expect(fixture.portal.sourceView === fixture.source)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)

    configuration.allowsHitTesting = true
    NativePortalViewRepresentable(sourceView: fixture.source, configuration: configuration)
      .configure(fixture.portal)

    #expect(fixture.portal.sourceView === fixture.source)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.button)
  }

  @Test
  func sourceRebindingPreservesTheSuppliedConfiguration() throws {
    let fixture = try PortalHitTestingFixture()
    let replacement = PortalPassthroughSourceView(frame: fixture.source.frame)
    fixture.root.addSubview(replacement)
    let configuration = PortalDestination.Configuration(
      matchesAlpha: true,
      matchesTransform: true,
      matchesPosition: true,
      allowsHitTesting: false,
      forwardsClientHitTestingToSourceView: false,
      hidesSourceView: false
    )

    NativePortalViewRepresentable(sourceView: replacement, configuration: configuration)
      .configure(fixture.portal)

    #expect(fixture.portal.sourceView === replacement)
    #expect(fixture.portal.matchesAlpha)
    #expect(fixture.portal.matchesTransform)
    #expect(fixture.portal.matchesPosition)
    #expect(!fixture.portal.allowsHitTesting)
    #expect(!fixture.portal.forwardsClientHitTestingToSourceView)
    #expect(!fixture.portal.hidesSourceView)
    #expect(fixture.portal.hitTest(fixture.buttonPoint, with: nil) == nil)
    #expect(fixture.portal.intrinsicContentSize == replacement.bounds.size)
  }

  @Test
  func liveConfigurationChangesHidingAndForwardingOnTheCurrentSource() throws {
    let fixture = try PortalHitTestingFixture()
    var configuration = PortalDestination.Configuration()
    configuration.hidesSourceView = false
    configuration.forwardsClientHitTestingToSourceView = false

    NativePortalViewRepresentable(sourceView: fixture.source, configuration: configuration)
      .configure(fixture.portal)

    #expect(fixture.portal.sourceView === fixture.source)
    #expect(!fixture.portal.hidesSourceView)
    #expect(!fixture.portal.forwardsClientHitTestingToSourceView)

    configuration.hidesSourceView = true
    configuration.forwardsClientHitTestingToSourceView = true
    NativePortalViewRepresentable(sourceView: fixture.source, configuration: configuration)
      .configure(fixture.portal)

    #expect(fixture.portal.sourceView === fixture.source)
    #expect(fixture.portal.hidesSourceView)
    #expect(fixture.portal.forwardsClientHitTestingToSourceView)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.button)
  }

  @Test
  func representableTeardownRestoresSourceAndClearsItsBinding() throws {
    let fixture = try PortalHitTestingFixture()
    let configuration = PortalDestination.Configuration(
      allowsHitTesting: false,
      forwardsClientHitTestingToSourceView: false,
      hidesSourceView: true
    )
    NativePortalViewRepresentable(sourceView: fixture.source, configuration: configuration)
      .configure(fixture.portal)

    NativePortalViewRepresentable.dismantleUIView(fixture.portal, coordinator: ())

    #expect(!fixture.portal.hidesSourceView)
    #expect(fixture.portal.sourceView == nil)
    #expect(fixture.destinationHit(at: fixture.buttonPoint) === fixture.background)
    let originalPoint = fixture.source.convert(fixture.buttonPoint, to: fixture.root)
    #expect(fixture.root.hitTest(originalPoint, with: nil) === fixture.button)
  }
}

/// Keeps both UIKit branches attached while hit tests traverse a shared ancestor.
@MainActor
private struct PortalHitTestingFixture {
  let window: UIWindow
  let root: UIView
  let background: UIView
  let source: PortalPassthroughSourceView
  let button: UIButton
  let portal: NativePortalView

  var buttonPoint: CGPoint {
    CGPoint(x: button.frame.midX, y: button.frame.midY)
  }

  init() throws {
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    root = UIView(frame: window.bounds)
    background = UIView(frame: root.bounds)
    source = PortalPassthroughSourceView(frame: CGRect(x: 20, y: 40, width: 160, height: 80))
    button = UIButton(frame: CGRect(x: 20, y: 12, width: 80, height: 40))
    portal = try #require(NativePortalView(sourceView: source))
    window.addSubview(root)
    root.addSubview(background)
    root.addSubview(source)
    source.addSubview(button)
    root.addSubview(portal)
    portal.frame = CGRect(x: 90, y: 330, width: 160, height: 80)
    portal.matchesAlpha = false
    portal.matchesPosition = false
    portal.matchesTransform = false
    portal.hidesSourceView = true
    portal.allowsHitTesting = true
    portal.forwardsClientHitTestingToSourceView = true
    portal.setNeedsLayout()
    portal.layoutIfNeeded()
  }

  func destinationHit(at point: CGPoint) -> UIView? {
    root.hitTest(portal.convert(point, to: root), with: nil)
  }
}

/// Models a source with interactive content and transparent regions that accept no hit.
@MainActor
private final class PortalPassthroughSourceView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}
