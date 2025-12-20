//
//  CellStateStorage.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/21.
//

import SwiftUI

/// Per-cell state storage using `@Observable` for automatic SwiftUI updates.
///
/// Each cell instance gets its own `CellStateStorage` that persists across cell reuse.
/// When `value` is modified, SwiftUI automatically re-renders the affected views.
///
/// ## Usage
///
/// Access via `CellContext.state` in your `TiledCellContent.body(context:)`:
///
/// ```swift
/// struct MyCell: TiledCellContent {
///   typealias StateValue = Int
///   let item: Message
///
///   func body(context: CellContext<Int>) -> some View {
///     let count = context.state.value
///
///     Button("Count: \(count)") {
///       context.state.value += 1
///     }
///   }
/// }
/// ```
@MainActor
@Observable
public final class CellStateStorage<Value> {

  /// The stored value. Modifications trigger SwiftUI re-renders.
  public var value: Value

  /// Creates a new storage with the given initial value.
  public init(_ initialValue: Value) {
    self.value = initialValue
  }
}
