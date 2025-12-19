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
/// The context provides access to reveal offset and other cell-related state
/// without needing to use `@Environment`.
///
/// ## Example
///
/// ```swift
/// struct MessageBubbleCell: TiledCellContent {
///   let item: Message
///
///   func body(context: CellContext) -> some View {
///     let offset = context.revealOffset(max: 60)
///
///     HStack {
///       MessageBubble(message: item)
///         .offset(x: -offset)
///
///       Text(item.timestamp.formatted())
///         .opacity(offset / 60)
///     }
///   }
/// }
///
/// // Usage in TiledView
/// TiledView(dataSource: dataSource, scrollPosition: $scrollPosition) { message, state in
///   MessageBubbleCell(item: message)
/// }
/// ```
public protocol TiledCellContent {
  associatedtype Item
  associatedtype Body: View

  /// The item this cell displays.
  var item: Item { get }

  /// Creates the view for this cell.
  ///
  /// - Parameter context: The cell context providing reveal offset and other state.
  /// - Returns: The view to display for this cell.
  @ViewBuilder
  func body(context: CellContext) -> Body
}

// MARK: - CellContext

/// Context provided to `TiledCellContent.body(context:)`.
///
/// Provides access to cell-related state without requiring `@Environment`.
public struct CellContext {

  /// The shared reveal state for swipe-to-reveal gesture.
  ///
  /// Returns `nil` when:
  /// - The view is not inside a `TiledView`
  /// - The `TiledView` has reveal disabled (`.revealConfiguration(.disabled)`)
  ///
  /// ## Example
  ///
  /// ```swift
  /// func body(context: CellContext) -> some View {
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

  init(cellReveal: CellReveal?) {
    self.cellReveal = cellReveal
  }
}

// MARK: - Internal Wrapper View

/// Internal view that wraps TiledCellContent and provides the context.
///
/// This view reads `cellReveal` from the environment and creates
/// a `CellContext` to pass to the content's `body(context:)` method.
public struct TiledCellContentWrapper<Content: TiledCellContent>: View {

  let content: Content

  @Environment(\.cellReveal) private var cellReveal

  public init(content: Content) {
    self.content = content
  }

  public var body: some View {
    content.body(context: CellContext(cellReveal: cellReveal))
  }
}
