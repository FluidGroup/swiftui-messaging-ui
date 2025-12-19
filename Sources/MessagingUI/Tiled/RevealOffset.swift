//
//  RevealOffset.swift
//  MessagingUI
//
//  Created by Claude on 2025/12/19.
//

import RubberBanding
import SwiftUI

// MARK: - CellReveal (Observable shared state)

/// Observable object that holds shared reveal state for all cells.
///
/// This object is shared across all cells and automatically triggers
/// SwiftUI updates when `offset` changes.
@MainActor
@Observable
public final class CellReveal {

  /// The raw horizontal reveal offset without rubber banding applied.
  /// - Value of `0` means fully hidden (default state)
  /// - Positive values indicate how far the user has swiped left
  ///
  /// Use `rubberbandedOffset(max:)` to get the offset with rubber band effect.
  public internal(set) var offset: CGFloat = 0

  public init() {}

  /// Returns the offset with rubber band effect applied beyond the max value.
  ///
  /// Each cell can specify its own max offset to control when rubber banding kicks in.
  ///
  /// - Parameters:
  ///   - max: The maximum offset before rubber banding starts
  ///   - bandLength: The rubber band length controlling stretchiness. Default is same as max.
  /// - Returns: Offset with rubber band effect applied when exceeding max
  public func rubberbandedOffset(max: CGFloat, bandLength: CGFloat? = nil) -> CGFloat {
    rubberBand(
      value: Double(offset),
      min: 0,
      max: Double(max),
      bandLength: Double(bandLength ?? max)
    )
  }
}

// MARK: - CellReveal Environment Key

private struct CellRevealKey: EnvironmentKey {
  static let defaultValue: CellReveal? = nil
}

extension EnvironmentValues {
  /// The shared reveal state for swipe-to-reveal gesture.
  ///
  /// Use this in your cell views to access the reveal offset and
  /// offset content to reveal timestamps or other information.
  ///
  /// Returns `nil` when:
  /// - The view is not inside a `TiledView`
  /// - The `TiledView` has reveal disabled (`.revealConfiguration(.disabled)`)
  ///
  /// When `nil`, use a fallback value of `0` for the offset to render
  /// the cell in its default (non-revealed) state.
  ///
  /// Example:
  /// ```swift
  /// struct MessageCell: View {
  ///   @Environment(\.cellReveal) private var cellReveal
  ///
  ///   var body: some View {
  ///     let offset = cellReveal?.rubberbandedOffset(max: 80) ?? 0
  ///     HStack {
  ///       MessageBubble()
  ///         .offset(x: -offset)
  ///
  ///       Text(timestamp)
  ///         .opacity(offset / 40)
  ///     }
  ///   }
  /// }
  /// ```
  public var cellReveal: CellReveal? {
    get { self[CellRevealKey.self] }
    set { self[CellRevealKey.self] = newValue }
  }
}

// MARK: - RevealConfiguration

/// Configuration for the swipe-to-reveal gesture.
///
/// Use this to enable or disable the reveal feature.
/// Each cell controls its own max offset via `CellReveal.rubberbandedOffset(max:)`.
///
/// ```swift
/// TiledView(...)
///   .revealConfiguration(.default)
/// ```
public struct RevealConfiguration: Equatable, Sendable {

  /// Whether the reveal feature is enabled.
  public var isEnabled: Bool

  /// Creates a reveal configuration.
  /// - Parameter isEnabled: Whether the feature is enabled. Default is true.
  public init(isEnabled: Bool = true) {
    self.isEnabled = isEnabled
  }

  /// Default configuration (enabled).
  public static var `default`: RevealConfiguration { .init() }

  /// Disabled configuration.
  public static var disabled: RevealConfiguration { .init(isEnabled: false) }
}
