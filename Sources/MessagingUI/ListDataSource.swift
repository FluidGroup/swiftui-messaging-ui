//
//  ListDataSource.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import DequeModule
import Foundation

// MARK: - ListDataSource

/// A data source that tracks changes for efficient list updates.
///
/// Instead of directly modifying an array, use this data source's methods
/// to modify items. This allows list views to know exactly what changed
/// and update accordingly without adjusting content offset.
public struct ListDataSource<Item: Identifiable & Equatable>: Equatable {

  // MARK: - Change

  public enum Change: Equatable {
    case setItems
    case prepend([Item.ID])
    case append([Item.ID])
    case update([Item.ID])
    case remove([Item.ID])
  }

  // MARK: - Properties

  /// Unique identifier for this data source instance.
  /// Used by TiledView to detect when the data source is replaced.
  public let id: UUID = UUID()

  /// Change counter used as cursor for tracking applied changes.
  public private(set) var changeCounter: Int = 0

  /// Internal storage using Deque for efficient prepend operations.
  private var _items: Deque<Item> = []

  /// The current items in the data source.
  public var items: [Item] { Array(_items) }

  /// Pending changes that haven't been consumed by TiledView yet.
  internal private(set) var pendingChanges: [Change] = []

  // MARK: - Initializers

  public init() {}

  public init(items: [Item]) {
    self._items = Deque(items)
    self.pendingChanges = [.setItems]
    self.changeCounter = 1
  }

  // MARK: - Mutation Methods

  /// Sets all items, replacing any existing items.
  /// Use this for initial load or complete refresh.
  public mutating func setItems(_ items: [Item]) {
    self._items = Deque(items)
    pendingChanges.append(.setItems)
    changeCounter += 1
  }

  /// Adds items to the beginning of the list.
  /// Use this for loading older content (e.g., older messages).
  public mutating func prepend(_ items: [Item]) {
    guard !items.isEmpty else { return }
    let ids = items.map { $0.id }
    for item in items.reversed() {
      self._items.prepend(item)
    }
    pendingChanges.append(.prepend(ids))
    changeCounter += 1
  }

  /// Adds items to the end of the list.
  /// Use this for loading newer content (e.g., new messages).
  public mutating func append(_ items: [Item]) {
    guard !items.isEmpty else { return }
    let ids = items.map { $0.id }
    self._items.append(contentsOf: items)
    pendingChanges.append(.append(ids))
    changeCounter += 1
  }

  /// Updates existing items by matching their IDs.
  /// Items that don't exist in the current list are ignored.
  public mutating func update(_ items: [Item]) {
    guard !items.isEmpty else { return }
    var updatedIds: [Item.ID] = []
    for item in items {
      if let index = self._items.firstIndex(where: { $0.id == item.id }) {
        self._items[index] = item
        updatedIds.append(item.id)
      }
    }
    if !updatedIds.isEmpty {
      pendingChanges.append(.update(updatedIds))
      changeCounter += 1
    }
  }

  /// Removes items with the specified IDs.
  public mutating func remove(ids: [Item.ID]) {
    guard !ids.isEmpty else { return }
    let idsSet = Set(ids)
    let removedIds = _items.filter { idsSet.contains($0.id) }.map { $0.id }
    self._items.removeAll { idsSet.contains($0.id) }
    if !removedIds.isEmpty {
      pendingChanges.append(.remove(removedIds))
      changeCounter += 1
    }
  }

  /// Removes a single item with the specified ID.
  public mutating func remove(id: Item.ID) {
    remove(ids: [id])
  }

  // MARK: - Equatable

  public static func == (lhs: ListDataSource<Item>, rhs: ListDataSource<Item>) -> Bool {
    // Compare id and items, not pendingChanges or changeCounter
    // Different id means different data source instance
    lhs.id == rhs.id && lhs.items == rhs.items
  }
}

// MARK: - Item.ID Hashable conformance for Set operations

extension ListDataSource where Item.ID: Hashable {

  /// Removes items with the specified IDs (optimized for Hashable IDs).
  public mutating func remove(ids: Set<Item.ID>) {
    guard !ids.isEmpty else { return }
    let removedIds = _items.filter { ids.contains($0.id) }.map { $0.id }
    self._items.removeAll { ids.contains($0.id) }
    if !removedIds.isEmpty {
      pendingChanges.append(.remove(removedIds))
      changeCounter += 1
    }
  }
}

// MARK: - Backward Compatibility

/// Backward compatibility alias for TiledDataSource.
@available(*, deprecated, renamed: "ListDataSource")
public typealias TiledDataSource<Item: Identifiable & Equatable> = ListDataSource<Item>
