//
//  TiledCellContent.swift
//  MessagingUI
//
//  Protocol for defining cell content in TiledView.
//

import SwiftUI

// MARK: - TiledCellContent Protocol

/// A protocol for defining cell content in TiledView.
///
/// Conforming types describe how to render a cell given an item and context.
/// The context provides access to reveal offset and per-cell state storage.
///
/// ## Example
///
/// ```swift
/// struct MessageBubbleCell: TiledCellContent {
///   typealias StateValue = Int  // Per-cell state type
///
///   let item: Message
///
///   func body(context: CellContext<Int>) -> some View {
///     let tapCount = context.state.value
///
///     MessageBubble(message: item)
///       .onTapGesture {
///         context.state.value += 1
///       }
///   }
/// }
///
/// // Usage in TiledView
/// TiledView(
///   dataSource: dataSource,
///   scrollPosition: $scrollPosition,
///   makeInitialState: { item in 0 }
/// ) { message in
///   MessageBubbleCell(item: message)
/// }
/// ```
public protocol TiledCellContent {
  associatedtype Item
  associatedtype StateValue
  associatedtype Body: View

  /// The item this cell displays.
  var item: Item { get }

  /// Creates the view for this cell.
  ///
  /// - Parameter context: The cell context providing reveal offset and per-cell state.
  /// - Returns: The view to display for this cell.
  @ViewBuilder
  func body(context: CellContext<StateValue>) -> Body
}

// MARK: - CellContext

/// Context provided to `TiledCellContent.body(context:)`.
///
/// Provides access to cell-related state including reveal offset and per-cell storage.
public struct CellContext<StateValue> {

  /// The shared reveal state for swipe-to-reveal gesture.
  ///
  /// Returns `nil` when:
  /// - The view is not inside a `TiledView`
  /// - The `TiledView` has reveal disabled (`.revealConfiguration(.disabled)`)
  ///
  /// ## Example
  ///
  /// ```swift
  /// func body(context: CellContext<MyState>) -> some View {
  ///   let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0
  ///
  ///   HStack {
  ///     content
  ///       .offset(x: -offset)
  ///
  ///     timestamp
  ///       .offset(x: 60 - offset)
  ///   }
  ///   .clipped()
  /// }
  /// ```
  public let cellReveal: CellReveal?

  /// Per-cell state storage.
  ///
  /// Access and modify per-cell state that persists across cell reuse.
  /// Changes to `state.value` automatically trigger SwiftUI re-renders.
  ///
  /// ## Example
  ///
  /// ```swift
  /// func body(context: CellContext<Int>) -> some View {
  ///   let count = context.state.value
  ///
  ///   Button("Tapped \(count) times") {
  ///     context.state.value += 1
  ///   }
  /// }
  /// ```
  public let state: CellStateStorage<StateValue>

  init(cellReveal: CellReveal?, state: CellStateStorage<StateValue>) {
    self.cellReveal = cellReveal
    self.state = state
  }
}

// MARK: - Internal Wrapper View

/// Internal view that wraps TiledCellContent and provides the context.
///
/// All dependencies are passed via init (no Environment usage).
public struct TiledCellContentWrapper<Content: TiledCellContent>: View {

  let content: Content
  let cellReveal: CellReveal?
  let state: CellStateStorage<Content.StateValue>

  public init(
    content: Content,
    cellReveal: CellReveal?,
    state: CellStateStorage<Content.StateValue>
  ) {
    self.content = content
    self.cellReveal = cellReveal
    self.state = state
  }

  public var body: some View {
    content.body(context: CellContext(
      cellReveal: cellReveal,
      state: state
    ))
  }
}
