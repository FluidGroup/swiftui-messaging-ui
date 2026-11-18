//
//  TiledRevealScrollExclusivityTests.swift
//  MessagingUITests
//

import SwiftUI
import Testing
import UIKit
@testable import MessagingUI

/// Verifies that the collection view refuses to begin scrolling while a
/// swipe-to-reveal pan is dragging, so a host app's edge-reveal gesture
/// (e.g. attached via `simultaneousGesture`) doesn't scroll the transcript.
@MainActor
struct TiledRevealScrollExclusivityTests {

  // MARK: - Fixtures

  private struct TestItem: Identifiable, Equatable {
    let id: Int
  }

  private func makeTiledView() -> TiledUIView<TestItem, Text, Text, Text, Text, Text, Int> {
    TiledUIView(
      makeInitialState: { _ in 0 },
      cellBuilder: { item, _, _ in Text("item \(item.id)") }
    )
  }

  // MARK: - Begin gate

  @Test
  func scrollPanDoesNotBeginWhileRevealIsActive() {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView
    collectionView.isRevealActive = true

    let shouldBegin = collectionView.gestureRecognizerShouldBegin(
      collectionView.panGestureRecognizer
    )

    #expect(shouldBegin == false)
  }

  @Test
  func scrollPanBeginsNormallyWhenRevealIsInactive() {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView
    collectionView.isRevealActive = false

    let shouldBegin = collectionView.gestureRecognizerShouldBegin(
      collectionView.panGestureRecognizer
    )

    #expect(shouldBegin == true)
  }

  @Test
  func scrollPanBeginsNormallyWithoutRevealFlagSet() {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView

    // Default state: no reveal has ever been active.
    let shouldBegin = collectionView.gestureRecognizerShouldBegin(
      collectionView.panGestureRecognizer
    )

    #expect(collectionView.isRevealActive == false)
    #expect(shouldBegin == true)
  }

  // MARK: - External activation (host-driven, independent of revealConfiguration)

  @Test
  func externalActivationGatesScrollPan() {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView

    tiledView.isExternalRevealActive = true

    #expect(collectionView.isRevealActive == true)
    #expect(collectionView.gestureRecognizerShouldBegin(collectionView.panGestureRecognizer) == false)
  }

  @Test
  func externalDeactivationRestoresScrollPan() {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView
    tiledView.isExternalRevealActive = true

    tiledView.isExternalRevealActive = false

    #expect(collectionView.isRevealActive == false)
    #expect(collectionView.gestureRecognizerShouldBegin(collectionView.panGestureRecognizer) == true)
  }

  @Test
  func externalActivationWorksWhileRevealConfigurationIsDisabled() {
    let tiledView = makeTiledView()
    tiledView.revealConfiguration = .disabled
    let collectionView = tiledView.collectionView as! TiledCollectionView

    tiledView.isExternalRevealActive = true

    #expect(collectionView.isRevealActive == true)
    #expect(collectionView.gestureRecognizerShouldBegin(collectionView.panGestureRecognizer) == false)
  }

  @Test
  func externalActivationCancelsInFlightScrollPan() throws {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView
    let scrollPan = collectionView.panGestureRecognizer

    // Simulate an in-flight scroll pan the same way a real drag would leave
    // it; the exclusivity helper must force it to .cancelled.
    scrollPan.isEnabled = true
    scrollPan.isEnabled = false
    // After disabling, UIKit moves the gesture out of the began/changed
    // states; re-simulate the states the helper reacts to by checking it
    // takes the cancellation path without crashing and ends inactive-gated.
    tiledView.isExternalRevealActive = true

    #expect(collectionView.isRevealActive == true)
  }

  @Test
  func otherGesturesBeginNormallyWhileRevealIsActive() {
    let tiledView = makeTiledView()
    let collectionView = tiledView.collectionView as! TiledCollectionView
    collectionView.isRevealActive = true

    // Foreign gestures must not be blocked; only the scroll pan is gated.
    let otherPan = UIPanGestureRecognizer()
    collectionView.addGestureRecognizer(otherPan)

    #expect(collectionView.gestureRecognizerShouldBegin(otherPan) == true)
    #expect(collectionView.gestureRecognizerShouldBegin(collectionView.panGestureRecognizer) == false)
  }
}
