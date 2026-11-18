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
