//
//  TiledDataSource.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import Foundation

// MARK: - TiledDataSource

/// A data source for TiledView that tracks changes for efficient updates.
///
/// Instead of directly modifying an array, use this data source's methods
/// to modify items. This allows TiledView to know exactly what changed
/// and update the layout accordingly without adjusting content offset.
public struct TiledDataSource<Item: Identifiable & Equatable>: Equatable {

  // MARK: - Change

  public enum Change: Equatable {
    case setItems([Item])
    case prepend([Item])
    case append([Item])
    case update([Item])
    case remove([Item.ID])
  }

  // MARK: - Properties

  /// Unique identifier for this data source instance.
  /// Used by TiledView to detect when the data source is replaced.
  public let id: UUID = UUID()

  /// Change counter used as cursor for tracking applied changes.
  public private(set) var changeCounter: Int = 0

  /// The current items in the data source.
  public private(set) var items: [Item] = []

  /// Pending changes that haven't been consumed by TiledView yet.
  internal private(set) var pendingChanges: [Change] = []

  // MARK: - Initializers

  public init() {}

  public init(items: [Item]) {
    self.items = items
    self.pendingChanges = [.setItems(items)]
    self.changeCounter = 1
  }

  // MARK: - Mutation Methods

  /// Sets all items, replacing any existing items.
  /// Use this for initial load or complete refresh.
  public mutating func setItems(_ items: [Item]) {
    self.items = items
    pendingChanges.append(.setItems(items))
    changeCounter += 1
  }

  /// Adds items to the beginning of the list.
  /// Use this for loading older content (e.g., older messages).
  public mutating func prepend(_ items: [Item]) {
    guard !items.isEmpty else { return }
    self.items.insert(contentsOf: items, at: 0)
    pendingChanges.append(.prepend(items))
    changeCounter += 1
  }

  /// Adds items to the end of the list.
  /// Use this for loading newer content (e.g., new messages).
  public mutating func append(_ items: [Item]) {
    guard !items.isEmpty else { return }
    self.items.append(contentsOf: items)
    pendingChanges.append(.append(items))
    changeCounter += 1
  }

  /// Updates existing items by matching their IDs.
  /// Items that don't exist in the current list are ignored.
  public mutating func update(_ items: [Item]) {
    guard !items.isEmpty else { return }
    var updatedItems: [Item] = []
    for item in items {
      if let index = self.items.firstIndex(where: { $0.id == item.id }) {
        self.items[index] = item
        updatedItems.append(item)
      }
    }
    if !updatedItems.isEmpty {
      pendingChanges.append(.update(updatedItems))
      changeCounter += 1
    }
  }

  /// Removes items with the specified IDs.
  public mutating func remove(ids: [Item.ID]) {
    guard !ids.isEmpty else { return }
    let idsSet = Set(ids)
    let removedIds = items.filter { idsSet.contains($0.id) }.map { $0.id }
    self.items.removeAll { idsSet.contains($0.id) }
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

  public static func == (lhs: TiledDataSource<Item>, rhs: TiledDataSource<Item>) -> Bool {
    // Compare id and items, not pendingChanges or changeCounter
    // Different id means different data source instance
    lhs.id == rhs.id && lhs.items == rhs.items
  }
}

// MARK: - Item.ID Hashable conformance for Set operations

extension TiledDataSource where Item.ID: Hashable {

  /// Removes items with the specified IDs (optimized for Hashable IDs).
  public mutating func remove(ids: Set<Item.ID>) {
    guard !ids.isEmpty else { return }
    let removedIds = items.filter { ids.contains($0.id) }.map { $0.id }
    self.items.removeAll { ids.contains($0.id) }
    if !removedIds.isEmpty {
      pendingChanges.append(.remove(removedIds))
      changeCounter += 1
    }
  }
}
