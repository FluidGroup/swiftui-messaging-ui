//
//  SpringAnimator.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/18.
//

import QuartzCore
import SwiftUI

/// A CADisplayLink-based animator that uses SwiftUI.Spring for smooth animations.
/// This is a generic animator that doesn't depend on any specific UI component.
@MainActor
final class SpringAnimator {

  // MARK: - Types

  /// Completion handler called when animation finishes or is cancelled
  typealias Completion = (_ finished: Bool) -> Void

  /// Handler called on each frame with the current animated value
  typealias OnUpdate = (_ value: Double) -> Void

  /// Result from target provider closure
  struct TargetResult {
    let target: Double
    let shouldStop: Bool
  }

  /// Provider closure called every frame to get dynamic target
  typealias TargetProvider = () -> TargetResult

  // MARK: - Properties

  /// The display link for frame-synchronized updates
  private nonisolated(unsafe) var displayLink: CADisplayLink?

  /// The spring configuration
  let spring: Spring

  /// Current animated value
  private(set) var currentValue: Double = 0

  /// Current velocity
  private(set) var currentVelocity: Double = 0

  /// Target value
  private(set) var targetValue: Double = 0

  /// Whether this is the first frame (to skip delta calculation)
  private var isFirstFrame: Bool = true

  /// Timestamp of the last frame
  private var lastTimestamp: CFTimeInterval = 0

  /// Completion handler
  private var completion: Completion?

  /// Update handler called on each frame
  private var onUpdate: OnUpdate?

  /// Target provider called every frame for dynamic target
  private var targetProvider: TargetProvider?

  /// Settling threshold - when value is within this range of target, consider settled
  var settlingThreshold: Double = 0.5

  /// Velocity threshold - when velocity is below this, consider settled
  var velocityThreshold: Double = 0.5

  /// Self-retention during animation to keep the animator alive
  private var retainedSelf: SpringAnimator?

  // MARK: - Initialization

  /// Creates a new SpringAnimator with the specified spring configuration.
  /// - Parameter spring: The spring to use for animation. Defaults to `.smooth`.
  init(spring: Spring = .smooth) {
    self.spring = spring
  }

  deinit {
    displayLink?.invalidate()
  }

  // MARK: - Public API

  /// Starts animating from the current value to the target value.
  /// - Parameters:
  ///   - from: The starting value. If nil, continues from current value.
  ///   - to: The target value
  ///   - initialVelocity: Optional initial velocity (units per second)
  ///   - onUpdate: Called on each frame with the current value
  ///   - completion: Called when animation completes or is cancelled
  func animate(
    from: Double? = nil,
    to target: Double,
    initialVelocity: Double = 0,
    onUpdate: @escaping OnUpdate,
    completion: Completion? = nil
  ) {
    // Stop any existing animation
    stop(finished: false)

    if let from {
      self.currentValue = from
    }
    self.targetValue = target
    self.targetProvider = nil
    self.currentVelocity = initialVelocity
    self.onUpdate = onUpdate
    self.completion = completion
    self.isFirstFrame = true

    // Retain self during animation
    self.retainedSelf = self

    // Create and start display link
    let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
    displayLink.add(to: .main, forMode: .common)
    self.displayLink = displayLink
  }

  /// Starts animating with a dynamic target that's evaluated every frame.
  /// - Parameters:
  ///   - from: The starting value. If nil, continues from current value.
  ///   - initialVelocity: Optional initial velocity (units per second)
  ///   - targetProvider: Called every frame to get current target and shouldStop flag
  ///   - onUpdate: Called on each frame with the current value
  ///   - completion: Called when animation completes or is cancelled
  func animate(
    from: Double? = nil,
    initialVelocity: Double = 0,
    targetProvider: @escaping TargetProvider,
    onUpdate: @escaping OnUpdate,
    completion: Completion? = nil
  ) {
    // Stop any existing animation
    stop(finished: false)

    if let from {
      self.currentValue = from
    }
    // Get initial target
    let initialResult = targetProvider()
    self.targetValue = initialResult.target
    self.targetProvider = targetProvider
    self.currentVelocity = initialVelocity
    self.onUpdate = onUpdate
    self.completion = completion
    self.isFirstFrame = true

    // Retain self during animation
    self.retainedSelf = self

    // Create and start display link
    let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
    displayLink.add(to: .main, forMode: .common)
    self.displayLink = displayLink
  }

  /// Stops the current animation.
  /// - Parameter finished: Whether the animation completed naturally
  func stop(finished: Bool = false) {
    displayLink?.invalidate()
    displayLink = nil

    let completionHandler = completion
    completion = nil
    onUpdate = nil
    targetProvider = nil

    // Release self-retention
    retainedSelf = nil

    completionHandler?(finished)
  }

  /// Whether an animation is currently running
  var isAnimating: Bool {
    displayLink != nil
  }

  // MARK: - Private Methods

  @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
    // Calculate delta time
    let deltaTime: TimeInterval
    if isFirstFrame {
      deltaTime = displayLink.targetTimestamp - displayLink.timestamp
      isFirstFrame = false
    } else {
      deltaTime = displayLink.targetTimestamp - lastTimestamp
    }
    lastTimestamp = displayLink.targetTimestamp

    // Clamp delta time to avoid large jumps (e.g., when app resumes from background)
    let clampedDeltaTime = min(deltaTime, 1.0 / 30.0)

    // Update target from provider if available
    var providerShouldStop = false
    if let targetProvider {
      let result = targetProvider()
      targetValue = result.target
      providerShouldStop = result.shouldStop
    }

    // Check if provider indicates immediate stop (already at destination)
    if providerShouldStop {
      currentValue = targetValue
      onUpdate?(currentValue)
      stop(finished: true)
      return
    }

    // Update spring values
    spring.update(
      value: &currentValue,
      velocity: &currentVelocity,
      target: targetValue,
      deltaTime: clampedDeltaTime
    )

    // Notify update
    onUpdate?(currentValue)

    // Check if animation has settled
    let distanceFromTarget = abs(currentValue - targetValue)
    let velocityMagnitude = abs(currentVelocity)

    if distanceFromTarget < settlingThreshold && velocityMagnitude < velocityThreshold {
      // Snap to final value
      currentValue = targetValue
      onUpdate?(currentValue)
      stop(finished: true)
    }
  }
}
