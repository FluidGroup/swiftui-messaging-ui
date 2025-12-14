//
//  CellState.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/14.
//

import Foundation

// MARK: - CustomStateKey

/// A type-safe key for custom cell state.
///
/// Define your custom state keys by conforming to this protocol:
/// ```swift
/// enum IsExpandedKey: CustomStateKey {
///   typealias Value = Bool
///   static var defaultValue: Bool { false }
/// }
/// ```
///
/// Then extend CellState for convenient access:
/// ```swift
/// extension CellState {
///   var isExpanded: Bool {
///     get { self[IsExpandedKey.self] }
///     set { self[IsExpandedKey.self] = newValue }
///   }
/// }
/// ```
public protocol CustomStateKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

// MARK: - CellState

/// Per-cell state storage using type-safe keys.
///
/// CellState provides a flexible way to store arbitrary state for each cell
/// without modifying the data model. State is managed by the list view and
/// passed to cells during configuration.
public struct CellState {

  /// An empty cell state instance.
  public static var empty: CellState { .init() }

  private var stateMap: [AnyKeyPath: Any] = [:]

  public init() {}

  /// Access state values using type-safe keys.
  public subscript<T: CustomStateKey>(key: T.Type) -> T.Value {
    get { stateMap[\T.self] as? T.Value ?? T.defaultValue }
    set { stateMap[\T.self] = newValue }
  }
}
