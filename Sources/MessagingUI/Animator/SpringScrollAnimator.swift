//
//  SpringScrollAnimator.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/18.
//

import UIKit
import SwiftUI

/// A scroll-specific animator that uses SpringAnimator internally.
/// Handles UIScrollView contentOffset animation with gesture cancellation support.
///
/// ## Why CADisplayLink instead of UIView animation?
///
/// `UIView.animate` and `UIViewPropertyAnimator` use CAAnimation internally,
/// which animates the **presentation layer** while setting the actual property
/// to the final value immediately.
///
/// However, `UIScrollView` operates with **dynamic animation**:
/// - `contentOffset` changes continuously during scrolling
/// - `scrollViewDidScroll` is called every frame
/// - Deceleration, bouncing, and paging are calculated in real-time
///
/// If we animate scroll using CAAnimation:
/// - The scroll appears to move visually (presentation layer)
/// - But `scrollViewDidScroll` is NOT called (actual value is already final)
/// - Scroll-position-dependent logic breaks (prepend triggers, geometry notifications, etc.)
///
/// By using CADisplayLink to update `contentOffset` every frame:
/// - `scrollViewDidScroll` fires every frame
/// - All scroll-dependent logic works correctly
/// - We can use custom `Spring` physics from SwiftUI
@MainActor
final class SpringScrollAnimator {

  // MARK: - Types

  /// Completion handler called when animation finishes or is cancelled
  typealias Completion = (_ finished: Bool) -> Void

  // MARK: - Properties

  /// The underlying spring animator
  private let animator: SpringAnimator

  /// The scroll view being animated
  private weak var scrollView: UIScrollView?

  /// Pan gesture recognizer observer for cancellation
  private var panGestureObservation: NSKeyValueObservation?

  /// Completion handler
  private var completion: Completion?

  /// Self-retention during animation to keep the animator alive
  private var retainedSelf: SpringScrollAnimator?

  // MARK: - Initialization

  /// Creates a new SpringScrollAnimator with the specified spring configuration.
  /// - Parameter spring: The spring to use for animation. Defaults to `.smooth`.
  init(spring: Spring = .smooth) {
    self.animator = SpringAnimator(spring: spring)
  }

  // MARK: - API

  /// Animates the scroll view's contentOffset.y to the target value.
  /// - Parameters:
  ///   - scrollView: The scroll view to animate
  ///   - targetOffsetY: The target contentOffset.y value
  ///   - initialVelocity: Optional initial velocity (points per second)
  ///   - completion: Called when animation completes or is cancelled
  func animate(
    scrollView: UIScrollView,
    to targetOffsetY: CGFloat,
    initialVelocity: CGFloat = 0,
    completion: Completion? = nil
  ) {
    // Stop any existing animation
    stop(finished: false)

    self.scrollView = scrollView
    self.completion = completion

    // Retain self during animation
    self.retainedSelf = self

    // Setup gesture cancellation
    setupGestureCancellation(for: scrollView)

    // Start the animation
    animator.animate(
      from: Double(scrollView.contentOffset.y),
      to: Double(targetOffsetY),
      initialVelocity: Double(initialVelocity),
      onUpdate: { [weak self, weak scrollView] value in
        guard let scrollView else {
          self?.stop(finished: false)
          return
        }
        var contentOffset = scrollView.contentOffset
        contentOffset.y = CGFloat(value)
        scrollView.contentOffset = contentOffset
      },
      completion: { [weak self] finished in
        self?.handleAnimationCompletion(finished: finished)
      }
    )
  }

  /// Stops the current animation.
  /// - Parameter finished: Whether the animation completed naturally
  func stop(finished: Bool = false) {
    animator.stop(finished: false)
    cleanupAndComplete(finished: finished)
  }

  /// Whether an animation is currently running
  var isAnimating: Bool {
    animator.isAnimating
  }

  // MARK: - Private Methods

  private func handleAnimationCompletion(finished: Bool) {
    cleanupAndComplete(finished: finished)
  }

  private func cleanupAndComplete(finished: Bool) {
    panGestureObservation?.invalidate()
    panGestureObservation = nil

    let completionHandler = completion
    completion = nil
    scrollView = nil

    // Release self-retention
    retainedSelf = nil

    completionHandler?(finished)
  }

  private func setupGestureCancellation(for scrollView: UIScrollView) {
    // Observe the pan gesture recognizer's state
    panGestureObservation = scrollView.panGestureRecognizer.observe(
      \.state,
      options: [.new]
    ) { [weak self] gestureRecognizer, _ in
      guard let self else { return }

      let state = gestureRecognizer.state
      if state == .began || state == .changed {
        // User started scrolling manually, cancel animation
        Task { @MainActor in
          self.stop(finished: false)
        }
      }
    }
  }
}
